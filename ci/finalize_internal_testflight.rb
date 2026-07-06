#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

class InternalTestFlightFinalizer
  API_BASE = "https://api.appstoreconnect.apple.com"
  DEFAULT_GROUP_NAMES = ["Internal Testers"].freeze
  ACCEPTED_INTERNAL_STATES = ["IN_BETA_TESTING"].freeze
  TRANSIENT_BUILD_STATES = ["PROCESSING", "UPLOAD_COMPLETE"].freeze

  class FinalizationError < StandardError; end

  def self.parse_group_names(value)
    groups = value.to_s.split(",").map(&:strip).reject(&:empty?)
    groups.empty? ? DEFAULT_GROUP_NAMES : groups
  end

  def self.select_groups(groups, requested_names)
    requested = requested_names.map(&:downcase)
    selected = groups.select do |group|
      requested.include?(group.fetch("name").to_s.downcase)
    end

    missing = requested_names.reject do |name|
      selected.any? { |group| group.fetch("name").to_s.casecmp(name).zero? }
    end

    [selected, missing]
  end

  def self.processed_build?(processing_state)
    processing_state.to_s == "VALID"
  end

  def self.failed_processing_state?(processing_state)
    state = processing_state.to_s
    !state.empty? && !processed_build?(state) && !TRANSIENT_BUILD_STATES.include?(state)
  end

  def self.internal_group?(group)
    value = group.dig("attributes", "isInternalGroup")
    value == true || value.to_s.casecmp("true").zero?
  end

  def self.internal_testing_state?(state)
    ACCEPTED_INTERNAL_STATES.include?(state.to_s)
  end

  def initialize(env: ENV, now: Time.now)
    @env = env
    @now = now
    @jwt_token = nil
  end

  def run
    app_id = required_env("APP_STORE_CONNECT_APP_ID")
    build_number = required_env("BUILD_NUMBER")
    marketing_version = @env.fetch("MARKETING_VERSION", "").to_s.strip
    requested_group_names = self.class.parse_group_names(@env.fetch("INTERNAL_GROUP_NAMES", ""))
    timeout_seconds = integer_env("WAIT_TIMEOUT_SECONDS", 1800)
    poll_seconds = integer_env("POLL_SECONDS", 30)

    puts "Finalizing internal TestFlight assignment"
    puts "App Store Connect app ID: #{app_id}"
    puts "Marketing version: #{marketing_version.empty? ? "any" : marketing_version}"
    puts "Build number: #{build_number}"
    puts "Internal groups: #{requested_group_names.join(", ")}"

    build = wait_for_processed_build(
      app_id: app_id,
      build_number: build_number,
      marketing_version: marketing_version,
      timeout_seconds: timeout_seconds,
      poll_seconds: poll_seconds
    )

    build_id = build.fetch("id")
    processing_state = build.dig("attributes", "processingState")
    version = build.dig("attributes", "version")
    puts "Build #{build_id} processed with processingState=#{processing_state} version=#{version}"

    groups = internal_groups(app_id)
    selected_groups, missing_groups = self.class.select_groups(groups, requested_group_names)
    unless missing_groups.empty?
      available = groups.map { |group| group.fetch("name") }.join(", ")
      raise FinalizationError,
            "Missing requested internal TestFlight group(s): #{missing_groups.join(", ")}. Available internal groups: #{available}"
    end

    add_build_to_groups(build_id, selected_groups)
    detail = wait_for_internal_testing_state(build_id, timeout_seconds: timeout_seconds, poll_seconds: poll_seconds)
    internal_state = detail.dig("attributes", "internalBuildState")

    puts "Assigned build #{build_id} to internal group(s): #{selected_groups.map { |group| group.fetch("name") }.join(", ")}"
    puts "Verified internalBuildState=#{internal_state}"
  end

  private

  def wait_for_processed_build(app_id:, build_number:, marketing_version:, timeout_seconds:, poll_seconds:)
    deadline = @now + timeout_seconds

    loop do
      build = find_build(app_id: app_id, build_number: build_number, marketing_version: marketing_version)
      if build
        processing_state = build.dig("attributes", "processingState")
        return build if self.class.processed_build?(processing_state)

        if self.class.failed_processing_state?(processing_state)
          raise FinalizationError, "Build #{build.fetch("id")} is not processable: processingState=#{processing_state}"
        end

        puts "Waiting for build #{build.fetch("id")} processingState=#{processing_state || "unknown"}"
      else
        puts "Waiting for build #{build_number} to appear in App Store Connect"
      end

      raise FinalizationError, "Timed out waiting for build #{build_number} to process." if Time.now >= deadline

      sleep poll_seconds
    end
  end

  def find_build(app_id:, build_number:, marketing_version:)
    params = {
      "filter[app]" => app_id,
      "filter[version]" => build_number,
      "fields[builds]" => "version,processingState,uploadedDate",
      "limit" => "10"
    }
    params["filter[preReleaseVersion.version]"] = marketing_version unless marketing_version.empty?

    builds = fetch_paginated_json("/v1/builds", params)
    builds.find { |build| build.dig("attributes", "version") == build_number }
  end

  def internal_groups(app_id)
    groups = fetch_paginated_json(
      "/v1/apps/#{app_id}/betaGroups",
      "fields[betaGroups]" => "name,isInternalGroup",
      "limit" => "200"
    )

    internal = groups.select { |group| self.class.internal_group?(group) }
    raise FinalizationError, "No internal TestFlight groups found for app #{app_id}." if internal.empty?

    internal.map do |group|
      {
        "id" => group.fetch("id"),
        "name" => group.dig("attributes", "name")
      }
    end
  end

  def add_build_to_groups(build_id, groups)
    post_json(
      "/v1/builds/#{build_id}/relationships/betaGroups",
      "data" => groups.map { |group| { "type" => "betaGroups", "id" => group.fetch("id") } },
      ignore_conflict: true
    )
  end

  def wait_for_internal_testing_state(build_id, timeout_seconds:, poll_seconds:)
    deadline = Time.now + timeout_seconds

    loop do
      detail = build_beta_detail(build_id)
      internal_state = detail.dig("attributes", "internalBuildState")
      return detail if self.class.internal_testing_state?(internal_state)

      raise FinalizationError, "Timed out waiting for internalBuildState=IN_BETA_TESTING. Last state: #{internal_state || "unknown"}" if Time.now >= deadline

      puts "Waiting for internalBuildState=IN_BETA_TESTING; current=#{internal_state || "unknown"}"
      sleep poll_seconds
    end
  end

  def build_beta_detail(build_id)
    fetch_single_json("/v1/builds/#{build_id}/buildBetaDetail", "fields[buildBetaDetails]" => "internalBuildState,externalBuildState")
  end

  def fetch_paginated_json(path, params)
    url = api_url(path, params)
    items = []

    loop do
      response = request_json(Net::HTTP::Get, url)
      data = response.fetch("data")
      raise FinalizationError, "Expected App Store Connect data array from #{url}." unless data.is_a?(Array)

      items.concat(data)
      next_url = response.dig("links", "next")
      break if next_url.to_s.empty?

      url = URI(next_url)
    end

    items
  end

  def fetch_single_json(path, params)
    data = request_json(Net::HTTP::Get, api_url(path, params)).fetch("data")
    raise FinalizationError, "Expected App Store Connect data object from #{path}." unless data.is_a?(Hash)

    data
  end

  def post_json(path, payload, ignore_conflict: false)
    request_json(Net::HTTP::Post, api_url(path, {}), payload: payload, ignore_conflict: ignore_conflict)
  end

  def request_json(request_class, url, payload: nil, ignore_conflict: false)
    request = request_class.new(url)
    request["Authorization"] = "Bearer #{jwt_token}"
    request["Accept"] = "application/json"
    if payload
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
    end

    response = Net::HTTP.start(
      url.hostname,
      url.port,
      use_ssl: url.scheme == "https",
      open_timeout: 10,
      read_timeout: 30
    ) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      return {} if ignore_conflict && response.is_a?(Net::HTTPConflict)

      raise FinalizationError, "App Store Connect request failed with HTTP #{response.code}: #{response.body}"
    end

    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  rescue JSON::ParserError => error
    raise FinalizationError, "App Store Connect returned invalid JSON: #{error.message}"
  end

  def api_url(path, params)
    url = URI.join(API_BASE, path)
    url.query = URI.encode_www_form(params) unless params.empty?
    url
  end

  def jwt_token
    @jwt_token ||= begin
      issued_at = @now.to_i - 60
      header = {
        alg: "ES256",
        kid: required_env("APP_STORE_CONNECT_KEY_ID"),
        typ: "JWT"
      }
      payload = {
        iss: required_env("APP_STORE_CONNECT_ISSUER_ID"),
        iat: issued_at,
        exp: issued_at + (20 * 60),
        aud: "appstoreconnect-v1"
      }

      signing_input = [base64url(header.to_json), base64url(payload.to_json)].join(".")
      signature = base64url(es256_signature(signing_input))
      "#{signing_input}.#{signature}"
    end
  end

  def es256_signature(signing_input)
    key = OpenSSL::PKey.read(File.read(required_env("APP_STORE_CONNECT_KEY_PATH")))
    der_signature = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
    sequence = OpenSSL::ASN1.decode(der_signature)

    r = sequence.value[0].value.to_i
    s = sequence.value[1].value.to_i
    hex_signature = [r.to_s(16).rjust(64, "0"), s.to_s(16).rjust(64, "0")].join
    [hex_signature].pack("H*")
  end

  def base64url(value)
    Base64.strict_encode64(value).tr("+/", "-_").delete("=")
  end

  def required_env(name)
    value = @env[name].to_s
    raise FinalizationError, "Missing required environment variable: #{name}" if value.empty?

    value
  end

  def integer_env(name, default)
    value = @env.fetch(name, default).to_s
    Integer(value)
  rescue ArgumentError
    raise FinalizationError, "#{name} must be an integer. Received: #{value}"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    InternalTestFlightFinalizer.new.run
  rescue InternalTestFlightFinalizer::FinalizationError => error
    warn error.message
    exit 1
  end
end
