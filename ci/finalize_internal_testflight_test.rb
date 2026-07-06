# frozen_string_literal: true

require "minitest/autorun"
require_relative "finalize_internal_testflight"

class InternalTestFlightFinalizerTest < Minitest::Test
  def test_parse_group_names_defaults_to_internal_testers
    assert_equal ["Internal Testers"], InternalTestFlightFinalizer.parse_group_names("")
    assert_equal ["Internal Testers"], InternalTestFlightFinalizer.parse_group_names(" , ")
  end

  def test_parse_group_names_trims_comma_separated_values
    assert_equal ["Internal Testers", "QA"], InternalTestFlightFinalizer.parse_group_names(" Internal Testers, QA ")
  end

  def test_select_groups_matches_case_insensitively_and_reports_missing
    groups = [
      { "id" => "group-1", "name" => "Internal Testers" },
      { "id" => "group-2", "name" => "QA" }
    ]

    selected, missing = InternalTestFlightFinalizer.select_groups(groups, ["internal testers", "Design"])

    assert_equal [{ "id" => "group-1", "name" => "Internal Testers" }], selected
    assert_equal ["Design"], missing
  end

  def test_processed_build_state
    assert InternalTestFlightFinalizer.processed_build?("VALID")
    refute InternalTestFlightFinalizer.processed_build?("PROCESSING")
  end

  def test_failed_processing_state
    refute InternalTestFlightFinalizer.failed_processing_state?("VALID")
    refute InternalTestFlightFinalizer.failed_processing_state?("PROCESSING")
    assert InternalTestFlightFinalizer.failed_processing_state?("FAILED")
  end

  def test_internal_group_accepts_boolean_or_string_true
    assert InternalTestFlightFinalizer.internal_group?({ "attributes" => { "isInternalGroup" => true } })
    assert InternalTestFlightFinalizer.internal_group?({ "attributes" => { "isInternalGroup" => "true" } })
    refute InternalTestFlightFinalizer.internal_group?({ "attributes" => { "isInternalGroup" => false } })
    refute InternalTestFlightFinalizer.internal_group?({ "attributes" => { "isInternalGroup" => "false" } })
  end

  def test_add_build_to_groups_posts_payload_and_uses_idempotent_conflict_handling
    recorder = Class.new(InternalTestFlightFinalizer) do
      attr_reader :posted

      def post_json(path, payload, ignore_conflict: false)
        @posted = { path: path, payload: payload, ignore_conflict: ignore_conflict }
      end
    end

    finalizer = recorder.allocate
    finalizer.send(:add_build_to_groups, "build-1", [{ "id" => "group-1" }])

    assert_equal "/v1/builds/build-1/relationships/betaGroups", finalizer.posted[:path]
    assert_equal({ "data" => [{ "type" => "betaGroups", "id" => "group-1" }] }, finalizer.posted[:payload])
    assert_equal true, finalizer.posted[:ignore_conflict]
  end

  def test_internal_testing_state_requires_in_beta_testing
    assert InternalTestFlightFinalizer.internal_testing_state?("IN_BETA_TESTING")
    refute InternalTestFlightFinalizer.internal_testing_state?("READY_FOR_BETA_TESTING")
  end

  def test_required_env_error_does_not_print_secret_values
    error = assert_raises(InternalTestFlightFinalizer::FinalizationError) do
      InternalTestFlightFinalizer.new(env: {}).send(:required_env, "APP_STORE_CONNECT_PRIVATE_KEY")
    end

    assert_equal "Missing required environment variable: APP_STORE_CONNECT_PRIVATE_KEY", error.message
  end
end
