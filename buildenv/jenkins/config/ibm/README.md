# IBM Java 8 Integration Testing Configuration

This directory contains configuration files for the IBM_Java8_J9_Integration pipeline, which is the dedicated pipeline for IBM Java 8 integration testing (equivalent to the legacy vmfarm/jsvtaxxon integration build).

## Purpose

These configurations define which test targets to run for IBM Java 8 integration testing, replacing the legacy jsvtaxxon system.

## Test Strategy

**Important:** The configuration uses `testList` with explicit test names rather than `sanity.jck` and `sanity.system` because:
- Other tests are already labeled as sanity in the test repositories
- Using `sanity.jck` or `sanity.system` would run ALL sanity tests (hours), not just the integration subset (15-25 mins)
- The `testList` approach ensures ONLY the specific 28 integration tests run

## Test Targets

All configurations run the integration test subset using `testList=<comma_separated_test_names>`:

### System Tests (10 tests from issue #35)
- iointerops_9
- interrupt_0, interrupt_3
- serbuf_0, serbuf.collocated_4
- abbs.5mins_1, abbs.5mins_3
- harmony.5mins_2
- Java_version
- mauve.5mins

### JCK Tests (18 tests from issue #35)
- jck-runtime-api-java_lang-serialization
- jck-runtime-api-java_lang-Runtime
- jck-runtime-api-java_util-treemap
- jck-runtime-api-java_util-Currency
- jck-runtime-api-java_util-Hashtable
- jck-runtime-api-java_util-LinkedList
- jck-runtime-api-java_util-concurrent_atomic
- jck-runtime-api-java_util-SimpleTimeZone
- jck-runtime-api-java_io-CharacterEncoding
- jck-runtime-api-java_io-FilePermission
- jck-runtime-api-java_io-PrintStream
- jck-runtime-api-java_nio-Buffer
- jck-runtime-api-java_security-algorithmparameters
- jck-runtime-api-java_security-KeyFactory
- jck-runtime-api-java_security-KeyPair
- jck-runtime-api-xsl-conf_node

**Total: 28 integration tests** (10 system + 18 JCK)

This subset runs in approximately 15-25 minutes, compared to hours for full sanity/extended test suites.

## Configuration Files

### Nightly Builds
- `nightly/jdk8.json` - Configuration for nightly integration builds
- `nightly/default.json` - Default configuration for other JDK versions

### Release Builds (FRT)
- `release/jdk8.json` - Configuration for Fix Release Testing (FRT)
- `release/default.json` - Default configuration for other JDK versions

### Weekly Builds
- `weekly/jdk8.json` - Configuration for weekly integration builds
- `weekly/default.json` - Default configuration for other JDK versions

### Reference File
- `integration_testlist.txt` - Human-readable list of all 28 integration tests (for reference only, not used by pipeline)

## Supported Platforms

All configurations support the following platforms:
- AIX: ppc32_aix, ppc64_aix
- Linux: ppc64le_linux, s390x_linux, x86-64_linux, x86-32_linux
- z/OS: s390_zos, s390x_zos
- Windows: x86-64_windows, x86-32_windows

## Pipeline Usage

The IBM_Java8_J9_Integration pipeline automatically reads these configuration files when:
- `VARIANT=ibm`
- `JDK_VERSIONS=8`
- `BUILD_TYPE=nightly|release|weekly`
- `CONFIG_JSON` parameter is empty (default)

### Example Pipeline Parameters

```
VARIANT: ibm
JDK_VERSIONS: 8
BUILD_TYPE: nightly
SDK_RESOURCE: customized
CUSTOMIZED_SDK_URL: https://espresso.hursley.ibm.com:8443/perl/secure/fetch/j9-80/Linux_AMD64/pxa6480sr9/20251222_01/ibm-java-sdk_x64_linux_8.0.9.0_20251222_01.tar.gz
CUSTOMIZED_SDK_URL_CREDENTIAL_ID: espresso_any_id
CONFIG_JSON: (leave empty to use config files)
```

## Schedule

The pipeline is scheduled to run at 10:30pm EST Monday to Saturday.

## Related Issues

- [#35](https://github.ibm.com/runtimes/automation/issues/35) - Integration Test Migration from Jsvtaxxon to Jenkins
- [#491](https://github.ibm.com/runtimes/automation/issues/491) - Create IBM Java 8 integration test pipeline
- [#546](https://github.ibm.com/runtimes/automation/issues/546) - Enable sanity.system for IBM Java 8 test pipeline

## Maintenance

### Updating the Test List

To add or remove tests from the integration test list:

1. Edit all config files (nightly, release, weekly - both jdk8.json and default.json)
2. Update the `testList=` value with the comma-separated test names
3. Update `integration_testlist.txt` for documentation
4. Test changes using Grinder before committing
5. Document changes in related GitHub issues

### Test Name Format

- **System tests**: Use the test target name (e.g., `iointerops_9`, `interrupt_0`)
- **JCK tests**: Use the format `jck-runtime-api-<package>-<test>` with underscores replacing dots (e.g., `jck-runtime-api-java_lang-serialization`)

### Synchronizing Config Files

All three build types (nightly, release, weekly) use the same test list. To keep them synchronized:

```bash
cd buildenv/jenkins/config/ibm
# After editing nightly configs, sync to others:
for dir in release weekly; do 
  cp nightly/jdk8.json $dir/jdk8.json
  cp nightly/default.json $dir/default.json
done
```

## Testing

### Using Grinder (for testing before committing)

```
TARGET: testList
TESTLIST: iointerops_9,interrupt_0,...(full list)
SDK: https://espresso.hursley.ibm.com:8443/perl/secure/fetch/...
VENDOR_TEST_REPOS: git@github.ibm.com:runtimes/SVTTestRepo.git,git@github.ibm.com:runtimes/jck.git
VENDOR_TEST_BRANCHES: main,main
VENDOR_TEST_DIRS: system,jck
```

### Using the Pipeline

Once config files are committed, simply trigger the pipeline with `BUILD_TYPE=nightly` and leave `CONFIG_JSON` empty.

## Notes

- The testList approach ensures precise control over which tests run
- No changes needed to test repository labels (sanity/extended/special)
- Other pipelines using sanity.jck or sanity.system are not affected
- BVT tests can be added to the testList when ready
