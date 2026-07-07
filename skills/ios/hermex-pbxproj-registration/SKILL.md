---
name: hermex-pbxproj-registration
description: Register new Swift source files in HermesMobile.xcodeproj/project.pbxproj (app or test target). Use whenever a task adds .swift files to this repo — the project uses explicit file references, NOT FileSystemSynchronized groups, so new files are invisible to the build until registered.
---

# Registering new source files in project.pbxproj

This project has **no `PBXFileSystemSynchronizedRootGroup`** — every source file
needs explicit pbxproj entries. SourceKit "Cannot find type … in scope"
diagnostics on brand-new files are usually just this; the build is authoritative.

## Procedure (4 edits per batch of files)

1. **Pick a unique 24-char hex ID prefix** for the batch and verify it's free:
   `grep -c "<PREFIX>" HermesMobile.xcodeproj/project.pbxproj` must return 0.
   Existing IDs are hand-rolled hex-ish strings (`1A2B3C4D…`, `FEEDBA00…`,
   `C0DE5700…`); stick to hex characters only. Number build-file IDs and
   file-reference IDs in separate ranges (e.g. `…01`-`…08` and `…11`-`…18`).

2. **PBXBuildFile section** (top of file, alphabet-ish clusters): one line per file
   ```
   <BUILD_ID> /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = <FILE_ID> /* Foo.swift */; };
   ```

3. **PBXFileReference section**: one line per file
   ```
   <FILE_ID> /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };
   ```

4. **Group tree**: add `<FILE_ID> /* Foo.swift */,` to the children of the owning
   PBXGroup. For a new feature directory, create a new PBXGroup (own ID, `path =
   <DirName>;`, `sourceTree = "<group>";`) and add it to the `Features` group
   (`1A2B3C4D5E6F7000000000C3`).

5. **Sources build phase**: add `<BUILD_ID> /* Foo.swift in Sources */,` to the
   correct target's `PBXSourcesBuildPhase` files list. App files → the phase
   containing e.g. `MemoryView.swift in Sources`; test files → the phase
   containing e.g. `ClarificationTests.swift in Sources`. The share extension
   and Live Activity widget targets have their own phases — only add files
   there deliberately.

6. **Verify with a build**, not with SourceKit:
   `xcodebuild -project HermesMobile.xcodeproj -scheme HermesMobile -destination 'platform=iOS Simulator,name=iPhone 17' build > /tmp/build.log 2>&1; echo exit:$?`
   (never pipe xcodebuild through a filter in the gating invocation — the
   filter's exit code masks failures).

## Non-goals

- Xcode GUI workflows (the maintainer uses VS Code; edits are text-based).
- Resource/asset registration (different sections; look at existing
  `PBXResourcesBuildPhase` entries if needed).
