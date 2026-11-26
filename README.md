# Introduction
The ParaBank demo web application and associated web services (SOAP and REST) from Parasoft.

# Run GitHub SOAtest tests on the local runner

On Windows, double-click `run-action-test.bat`, or run:

```powershell
.\run-action-test.bat -ActionRef master
```

This starts `D:\Github-runner\parabank-soatest-runner\run.cmd`, updates and commits the
SOAtest workflow, pushes to `master`, and waits for the GitHub Actions result.
It uses the `self-hosted` label and the runner's registered name (`CD-LYAO-02`) as a
specific scheduling label. The default suite is `Smoke.tst`, targeting port `8080`.
See [scripts/README.md](scripts/README.md) for prerequisites, suite selection, credentials,
and `-PrepareOnly` to review the workflow locally without pushing.

# Run locally

Requires a JDK (Java 11 or 17 recommended) and Maven 3.6.3 or later on `PATH`.
The repository includes Tomcat 9; no separate database or message broker is required.

From the project directory, run:

```bat
:: Windows (Command Prompt or PowerShell)
.\start.bat
```

```bash
# Linux / macOS / Git Bash
bash ./start.sh
```

The scripts build the application and run it in the bundled Tomcat using Maven Cargo.
Open http://localhost:8080/parabank/ after Tomcat finishes starting.
The sample account is `john` / `demo`.
Press `Ctrl+C` in the startup terminal to stop the server.

The equivalent Maven command is:

```bash
mvn -DskipTests package cargo:run
```

To use another HTTP port, pass `-Dcargo.servlet.port=18080` to the script or Maven command.
The runtime configuration, deployed application, logs and database files are stored under
`target/cargo/`; `mvn clean` removes that local runtime data. The first build requires
network access to download Maven dependencies. Ports `9001` (HyperSQL), `61616` (ActiveMQ),
and `8205` (Tomcat shutdown) must also be available.

# Build and Install

Build and run the unit tests with `mvn clean package`. The deployable application is
`target/parabank.war`. To install it into the local Maven repository without running the
browser integration tests, use `mvn clean install -DskipITs`.
The separate SOAtest project remains available with `mvn -f soatest/pom.xml ...` and
requires a configured SOAtest installation.

1. Deploy `target/parabank.war` into an Apache Tomcat 9 container, or use the local startup scripts above.

NOTE: if using the coverage agent when running the functional/manual tests (see below), execute the build using "mvn -Dmaven.test.skip=true clean install jtest:monitor"

* ParaBank uses a built-in HyperSQL database. You must shut down all running instances of **ParaBank** and *HyperSQL* for the build to succeed. Otherwise several tests may fail, since there are a number of ports that are shared between the test instances and the real thing. See [changing default ports](#changing-default-ports).

## Apache Tomcat notes
* Java `8` or `11` is recommended. Oracle JDK or Zulu OpenJDK is preferred.

* Apache Tomcat `8.5` or `9` is recommended.

* To prevent verbose cache warnings in the tomcat log::

 ```text
 Oct 06, 2016 3:53:33 PM org.apache.catalina.webresources.Cache getResource
 WARNING: Unable to add the resource at [/WEB-INF/lib/wss4j-ws-security-stax-2.1.3.jar] to the cache because there was insufficient free space available after evicting expired cache entries - consider increasing the maximum size of the cache
 ```

Add the following to the `<tomcat install>/config/context.xml` make sure to place this block before `</Context>` tag. This setting will provide `100 MB`  for caching:

  ```xml
  <Resources cachingAllowed="true" cacheMaxSize="102400" />
  ```
* To support clean re-deployments of **ParaBank** please add the following to the `<Context>` tag of the `<tomcat install>/config/context.xml`

 ```xml
 <Context antiResourceLocking="true">
 ```

## Changing default ports
HyperSQL listens on the default port number `9001`. This port number can conflict with other instances of HyperSQL and may conflict with certain other applications such as the "Intel(R) Graphics Command Center Service". To change the port number to something else like `9002` , modify the following files located under "src/main/resources" or in a deployed WAR under "WEB-INF/classes":

* **applicationContext-hsqldb.xml**: This file configures HyperSQL. Look for the "hsqldb" bean and its "props". Add the following "prop", giving it the desired port number:

```
<prop key="server.port">9002</prop>
```

* **jdbc.properties**: This file configures the JDBC client connection used by ParaBank. Change "jdbc.url" to include the desired port number:

```
jdbc.url=jdbc:hsqldb:hsql://localhost:9002/parabank
```

* **jdbcBookstore.properties**: This file configures the JDBC client connection used by Bookstore. Change the following properties to include the desired port number:

```
jdbc.bookstoreURL=jdbc:hsqldb:hsql://localhost:9002/bookstore
jdbc.bookstorePort=9002
```

Apache ActiveMQ listens on the default port number `61616`. This port number can conflict with other instances of ActiveMQ. To change the default port number to something else like `61617`, modify the following file located under "src/main/resources" or in a deployed WAR under "WEB-INF/classes":

* **applicationContext-jms.xml**: This file configures ActiveMQ. Modify the port number in the "uri" for the transportConnector:

```
<amq:transportConnector uri="tcp://0.0.0.0:61617?transport.daemon=true" />
```

# Test scripts
* All scripts exist in two flavors (.bat and .sh) for Windows and Linux respectively.
* All scripts should be executed from project directory and require the following Parasoft products (and versions)
** Parasoft DTP 5.3.2
** Parasoft Jtest 10.3.2
** Parasoft SOAtest 9.10.1

Script                                 | Description
-------------------------------------- | -----------
__deploy-jtest-monitor(.sh\|.bat)__    | Deploys the Jtest Monitor package (created using mvn goal jtest:monitor) into directory specified by APP_COVERAGE_DIR in `set-vars(.sh|.bat)`
__jtest-ft-cov(.sh\|.bat)__            | Executes Parasoft Jtest DTP Engine for processing monitored coverage during functional testing with SOAtest
__jtest-mt-cov(.sh\|.bat)__            | Uploads results from manual testing efforts (managed using the Parasoft Coverage Agent Manager) and processing coverage data captured during manual testing
__jtest-sa-ut(.sh\|.bat)__             | Executes Parasoft Jtest DTP Engine for Static Analysis and Unit Testing results/coverage
__jtest-sa-ut-delta(.sh\|.bat)__       | Same operation as `jtest-sa-ut(.sh|.bat)` but used to rescan code based for localized changes - used for demonstration purposes when scanning 'dirty' branch
__set-vars(.sh\|.bat)__                | Utility script called by other scripts to consistently set BUILD_ID and the Project name sent to DTP
__soatest(.sh\|.bat)__                 | Executes Parasoft SOAtest API and Web functional tests (including integration with Jtest DTP Engine for monitoring code coverage)

## Setup
set-vars.(.sh\|.bat): setup JTEST_HOME and SOATEST_HOME environment variable before running any script.
all reports will be stored under target/report/<build ID> directory.
on Windows, 7zip must be installed (default to C:\Program Files\7-zip) to run deploy-jtest-monitor.bat script.
