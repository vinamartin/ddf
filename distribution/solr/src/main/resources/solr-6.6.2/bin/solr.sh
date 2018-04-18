#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# CONTROLLING STARTUP:
#
# Use solr -help to see available command-line options. In addition
# to passing command-line options, this script looks for an include
# file named solr.in.sh to set environment variables. Specifically, 
# the following locations are searched in this order:
#
# ./
# $HOME/.solr.in.sh
# /usr/share/solr
# /usr/local/share/solr
# /var/solr/
# /opt/solr
#
# Another option is to specify the full path to the include file in the
# environment. For example:
#
#   $ SOLR_INCLUDE=/path/to/solr.in.sh solr start
#
# Note: This is particularly handy for running multiple instances on a 
# single installation, or for quick tests.
#
# Finally, developers and enthusiasts who frequently run from an SVN 
# checkout, and do not want to locally modify bin/solr.in.sh, can put
# a customized include file at ~/.solr.in.sh.
#
# If you would rather configure startup entirely from the environment, you
# can disable the include by exporting an empty SOLR_INCLUDE, or by 
# ensuring that no include files exist in the aforementioned search list.

SOLR_SCRIPT="$0"
verbose=false
THIS_OS=`uname -s`

# What version of Java is required to run this version of Solr.
JAVA_VER_REQ="1.8"

stop_all=false

# for now, we don't support running this script from cygwin due to problems
# like not having lsof, ps auxww, curl, and awkward directory handling
if [ "${THIS_OS:0:6}" == "CYGWIN" ]; then
  echo -e "This script does not support cygwin due to severe limitations and lack of adherence\nto BASH standards, such as lack of lsof, curl, and ps options.\n\nPlease use the native solr.cmd script on Windows!"
  exit 1
fi

# Resolve symlinks to this script
while [ -h "$SOLR_SCRIPT" ] ; do
  ls=`ls -ld "$SOLR_SCRIPT"`
  # Drop everything prior to ->
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    SOLR_SCRIPT="$link"
  else
    SOLR_SCRIPT=`dirname "$SOLR_SCRIPT"`/"$link"
  fi
done

SOLR_TIP=`dirname "$SOLR_SCRIPT"`/..
SOLR_TIP=`cd "$SOLR_TIP"; pwd`
DEFAULT_SERVER_DIR="$SOLR_TIP/server"

# If an include wasn't specified in the environment, then search for one...
if [ -z "$SOLR_INCLUDE" ]; then
  # Locations (in order) to use when searching for an include file.
  for include in "`dirname "$0"`/solr.in.sh" \
               "$HOME/.solr.in.sh" \
               /usr/share/solr/solr.in.sh \
               /usr/local/share/solr/solr.in.sh \
               /etc/default/solr.in.sh \
               /opt/solr/solr.in.sh; do
    if [ -r "$include" ]; then
        SOLR_INCLUDE="$include"
        . "$include"
        break
    fi
  done
elif [ -r "$SOLR_INCLUDE" ]; then
  . "$SOLR_INCLUDE"
fi

if [ -z "$SOLR_PID_DIR" ]; then
  SOLR_PID_DIR="$SOLR_TIP/bin"
fi

if [ -n "$SOLR_JAVA_HOME" ]; then
  JAVA="$SOLR_JAVA_HOME/bin/java"
elif [ -n "$JAVA_HOME" ]; then
  for java in "$JAVA_HOME"/bin/amd64/java "$JAVA_HOME"/bin/java; do
    if [ -x "$java" ]; then
      JAVA="$java"
      break
    fi
  done
  if [ -z "$JAVA" ]; then
    echo >&2 "The currently defined JAVA_HOME ($JAVA_HOME) refers"
    echo >&2 "to a location where Java could not be found.  Aborting."
    echo >&2 "Either fix the JAVA_HOME variable or remove it from the"
    echo >&2 "environment so that the system PATH will be searched."
    exit 1
  fi
else
  JAVA=java
fi

if [ -z "$SOLR_STOP_WAIT" ]; then
  SOLR_STOP_WAIT=180
fi
# test that Java exists, is executable and correct version
JAVA_VER=$("$JAVA" -version 2>&1)
if [[ $? -ne 0 ]] ; then
  echo >&2 "Java not found, or an error was encountered when running java."
  echo >&2 "A working Java $JAVA_VER_REQ JRE is required to run Solr!"
  echo >&2 "Please install latest version of Java $JAVA_VER_REQ or set JAVA_HOME properly."
  echo >&2 "Command that we tried: '${JAVA} -version', with response:"
  echo >&2 "${JAVA_VER}"
  echo >&2
  echo >&2 "Debug information:"
  echo >&2 "JAVA_HOME: ${JAVA_HOME:-N/A}"
  echo >&2 "Active Path:"
  echo >&2 "${PATH}"
  exit 1
else
  JAVA_VER_NUM=$(echo $JAVA_VER | head -1 | awk -F '"' '/version/ {print $2}')
  if [[ "$JAVA_VER_NUM" < "$JAVA_VER_REQ" ]] ; then
    echo >&2 "Your current version of Java is too old to run this version of Solr"
    echo >&2 "We found version $JAVA_VER_NUM, using command '${JAVA} -version', with response:"
    echo >&2 "${JAVA_VER}"
    echo >&2
    echo >&2 "Please install latest version of Java $JAVA_VER_REQ or set JAVA_HOME properly."
    echo >&2
    echo >&2 "Debug information:"
    echo >&2 "JAVA_HOME: ${JAVA_HOME:-N/A}"
    echo >&2 "Active Path:"
    echo >&2 "${PATH}"
    exit 1
  fi
  JAVA_VENDOR="Oracle"
  if [ "`echo $JAVA_VER | grep -i "IBM J9"`" != "" ]; then
      JAVA_VENDOR="IBM J9"
  fi
fi


# Select HTTP OR HTTPS related configurations
SOLR_URL_SCHEME=http
SOLR_JETTY_CONFIG=()
SOLR_SSL_OPTS=""
if [ -n "$SOLR_SSL_KEY_STORE" ]; then
  SOLR_JETTY_CONFIG+=("--module=https")
  SOLR_URL_SCHEME=https
  SOLR_SSL_OPTS+=" -Dsolr.jetty.keystore=$SOLR_SSL_KEY_STORE"
  if [ -n "$SOLR_SSL_KEY_STORE_PASSWORD" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.keystore.password=$SOLR_SSL_KEY_STORE_PASSWORD"
  fi
  if [ -n "$SOLR_SSL_KEY_STORE_TYPE" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.keystore.type=$SOLR_SSL_KEY_STORE_TYPE"
  fi

  if [ -n "$SOLR_SSL_TRUST_STORE" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.truststore=$SOLR_SSL_TRUST_STORE"
  fi
  if [ -n "$SOLR_SSL_TRUST_STORE_PASSWORD" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.truststore.password=$SOLR_SSL_TRUST_STORE_PASSWORD"
  fi
  if [ -n "$SOLR_SSL_TRUST_STORE_TYPE" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.truststore.type=$SOLR_SSL_TRUST_STORE_TYPE"
  fi

  if [ -n "$SOLR_SSL_NEED_CLIENT_AUTH" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.ssl.needClientAuth=$SOLR_SSL_NEED_CLIENT_AUTH"
  fi
  if [ -n "$SOLR_SSL_WANT_CLIENT_AUTH" ]; then
    SOLR_SSL_OPTS+=" -Dsolr.jetty.ssl.wantClientAuth=$SOLR_SSL_WANT_CLIENT_AUTH"
  fi

  if [ -n "$SOLR_SSL_CLIENT_KEY_STORE" ]; then
    SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStore=$SOLR_SSL_CLIENT_KEY_STORE"

    if [ -n "$SOLR_SSL_CLIENT_KEY_STORE_PASSWORD" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStorePassword=$SOLR_SSL_CLIENT_KEY_STORE_PASSWORD"
    fi
    if [ -n "$SOLR_SSL_CLIENT_KEY_STORE_TYPE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStoreType=$SOLR_SSL_CLIENT_KEY_STORE_TYPE"
    fi
  else
    if [ -n "$SOLR_SSL_KEY_STORE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStore=$SOLR_SSL_KEY_STORE"
    fi
    if [ -n "$SOLR_SSL_KEY_STORE_PASSWORD" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStorePassword=$SOLR_SSL_KEY_STORE_PASSWORD"
    fi
    if [ -n "$SOLR_SSL_KEY_STORE_TYPE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.keyStoreType=$SOLR_SSL_KEYSTORE_TYPE"
    fi
  fi

  if [ -n "$SOLR_SSL_CLIENT_TRUST_STORE" ]; then
    SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStore=$SOLR_SSL_CLIENT_TRUST_STORE"

    if [ -n "$SOLR_SSL_CLIENT_TRUST_STORE_PASSWORD" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStorePassword=$SOLR_SSL_CLIENT_TRUST_STORE_PASSWORD"
    fi

    if [ -n "$SOLR_SSL_CLIENT_TRUST_STORE_TYPE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStoreType=$SOLR_SSL_CLIENT_TRUST_STORE_TYPE"
    fi
  else
    if [ -n "$SOLR_SSL_TRUST_STORE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStore=$SOLR_SSL_TRUST_STORE"
    fi

    if [ -n "$SOLR_SSL_TRUST_STORE_PASSWORD" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStorePassword=$SOLR_SSL_TRUST_STORE_PASSWORD"
    fi

    if [ -n "$SOLR_SSL_TRUST_STORE_TYPE" ]; then
      SOLR_SSL_OPTS+=" -Djavax.net.ssl.trustStoreType=$SOLR_SSL_TRUST_STORE_TYPE"
    fi
  fi
else
  SOLR_JETTY_CONFIG+=("--module=http")
fi

# Authentication options
if [ -z "$SOLR_AUTH_TYPE" ] && [ -n "$SOLR_AUTHENTICATION_OPTS" ]; then
  echo "WARNING: SOLR_AUTHENTICATION_OPTS environment variable configured without associated SOLR_AUTH_TYPE variable"
  echo "         Please configure SOLR_AUTH_TYPE environment variable with the authentication type to be used."
  echo "         Currently supported authentication types are [kerberos, basic]"
fi

if [ -n "$SOLR_AUTH_TYPE" ] && [ -n "$SOLR_AUTHENTICATION_CLIENT_CONFIGURER" ]; then
  echo "WARNING: SOLR_AUTHENTICATION_CLIENT_CONFIGURER and SOLR_AUTH_TYPE environment variables are configured together."
  echo "         Use SOLR_AUTH_TYPE environment variable to configure authentication type to be used. "
  echo "         Currently supported authentication types are [kerberos, basic]"
  echo "         The value of SOLR_AUTHENTICATION_CLIENT_CONFIGURER environment variable will be ignored"
fi

if [ -n "$SOLR_AUTH_TYPE" ]; then
  case "$(echo $SOLR_AUTH_TYPE | awk '{print tolower($0)}')" in
    basic)
      SOLR_AUTHENTICATION_CLIENT_CONFIGURER="org.apache.solr.client.solrj.impl.PreemptiveBasicAuthConfigurer"
      ;;
    kerberos)
      SOLR_AUTHENTICATION_CLIENT_CONFIGURER="org.apache.solr.client.solrj.impl.Krb5HttpClientConfigurer"
      ;;
    *)
      echo "ERROR: Value specified for SOLR_AUTH_TYPE environment variable is invalid."
      exit 1
   esac
fi

if [ "$SOLR_AUTHENTICATION_CLIENT_CONFIGURER" != "" ]; then
  AUTHC_CLIENT_CONFIGURER_ARG="-Dsolr.httpclient.builder.factory=$SOLR_AUTHENTICATION_CLIENT_CONFIGURER"
fi
AUTHC_OPTS="$AUTHC_CLIENT_CONFIGURER_ARG $SOLR_AUTHENTICATION_OPTS"

# Set the SOLR_TOOL_HOST variable for use when connecting to a running Solr instance
if [ "$SOLR_HOST" != "" ]; then
  SOLR_TOOL_HOST="$SOLR_HOST"
else
  SOLR_TOOL_HOST="localhost"
fi

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"
    
  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG\n"
  fi
  
  if [ -z "$CMD" ]; then
    echo ""
    echo "Usage: solr COMMAND OPTIONS"
    echo "       where COMMAND is one of: start, stop, restart, status, healthcheck, create, create_core, create_collection, delete, version, zk, auth"
    echo ""
    echo "  Standalone server example (start Solr running in the background on port 8984):"
    echo ""
    echo "    ./solr start -p 8984"
    echo ""
    echo "  SolrCloud example (start Solr running in SolrCloud mode using localhost:2181 to connect to Zookeeper, with 1g max heap size and remote Java debug options enabled):"
    echo ""
    echo "    ./solr start -c -m 1g -z localhost:2181 -a \"-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=1044\""
    echo ""
    echo "Pass -help after any COMMAND to see command-specific usage information,"
    echo "  such as:    ./solr start -help or ./solr stop -help"
    echo ""
  elif [[ "$CMD" == "start" || "$CMD" == "restart" ]]; then
    echo ""
    echo "Usage: solr $CMD [-f] [-c] [-h hostname] [-p port] [-d directory] [-z zkHost] [-m memory] [-e example] [-s solr.solr.home] [-a \"additional-options\"] [-V]"
    echo ""
    echo "  -f            Start Solr in foreground; default starts Solr in the background"
    echo "                  and sends stdout / stderr to solr-PORT-console.log"
    echo ""
    echo "  -c or -cloud  Start Solr in SolrCloud mode; if -z not supplied, an embedded Zookeeper"
    echo "                  instance is started on Solr port+1000, such as 9983 if Solr is bound to 8983"
    echo ""
    echo "  -h <host>     Specify the hostname for this Solr instance"
    echo ""
    echo "  -p <port>     Specify the port to start the Solr HTTP listener on; default is 8983"
    echo "                  The specified port (SOLR_PORT) will also be used to determine the stop port"
    echo "                  STOP_PORT=(\$SOLR_PORT-1000) and JMX RMI listen port RMI_PORT=(\$SOLR_PORT+10000). "
    echo "                  For instance, if you set -p 8985, then the STOP_PORT=7985 and RMI_PORT=18985"
    echo ""
    echo "  -d <dir>      Specify the Solr server directory; defaults to server"
    echo ""
    echo "  -z <zkHost>   Zookeeper connection string; only used when running in SolrCloud mode using -c"
    echo "                   To launch an embedded Zookeeper instance, don't pass this parameter."
    echo ""
    echo "  -m <memory>   Sets the min (-Xms) and max (-Xmx) heap size for the JVM, such as: -m 4g"
    echo "                  results in: -Xms4g -Xmx4g; by default, this script sets the heap size to 512m"
    echo ""
    echo "  -s <dir>      Sets the solr.solr.home system property; Solr will create core directories under"
    echo "                  this directory. This allows you to run multiple Solr instances on the same host"
    echo "                  while reusing the same server directory set using the -d parameter. If set, the"
    echo "                  specified directory should contain a solr.xml file, unless solr.xml exists in Zookeeper."
    echo "                  This parameter is ignored when running examples (-e), as the solr.solr.home depends"
    echo "                  on which example is run. The default value is server/solr."
    echo ""
    echo "  -e <example>  Name of the example to run; available examples:"
    echo "      cloud:         SolrCloud example"
    echo "      techproducts:  Comprehensive example illustrating many of Solr's core capabilities"
    echo "      dih:           Data Import Handler"
    echo "      schemaless:    Schema-less example"
    echo ""
    echo "  -a            Additional parameters to pass to the JVM when starting Solr, such as to setup"
    echo "                  Java debug options. For example, to enable a Java debugger to attach to the Solr JVM"
    echo "                  you could pass: -a \"-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=18983\""
    echo "                  In most cases, you should wrap the additional parameters in double quotes."
    echo ""
    echo "  -noprompt     Don't prompt for input; accept all defaults when running examples that accept user input"
    echo ""
    echo "  -v and -q     Verbose (-v) or quiet (-q) logging. Sets default log level to DEBUG or WARN instead of INFO"
    echo ""
    echo "  -V or -verbose Verbose messages from this script"
    echo ""
  elif [ "$CMD" == "stop" ]; then
    echo ""
    echo "Usage: solr stop [-k key] [-p port] [-V]"
    echo ""
    echo "  -k <key>      Stop key; default is solrrocks"
    echo ""
    echo "  -p <port>     Specify the port the Solr HTTP listener is bound to"
    echo ""
    echo "  -all          Find and stop all running Solr servers on this host"
    echo ""
    echo "  NOTE: To see if any Solr servers are running, do: solr status"
    echo ""
  elif [ "$CMD" == "healthcheck" ]; then
    echo ""
    echo "Usage: solr healthcheck [-c collection] [-z zkHost]"
    echo ""
    echo "  -c <collection>  Collection to run healthcheck against."
    echo ""
    echo "  -z <zkHost>      Zookeeper connection string; default is localhost:9983"
    echo ""
  elif [ "$CMD" == "status" ]; then
    echo ""
    echo "Usage: solr status"
    echo ""
    echo "  NOTE: This command will show the status of all running Solr servers"
    echo ""
  elif [ "$CMD" == "create" ]; then
    echo ""
    echo "Usage: solr create [-c name] [-d confdir] [-n configName] [-shards #] [-replicationFactor #] [-p port]"
    echo ""
    echo "  Create a core or collection depending on whether Solr is running in standalone (core) or SolrCloud"
    echo "  mode (collection). In other words, this action detects which mode Solr is running in, and then takes"
    echo "  the appropriate action (either create_core or create_collection). For detailed usage instructions, do:"
    echo ""
    echo "    bin/solr create_core -help"
    echo ""
    echo "       or"
    echo ""
    echo "    bin/solr create_collection -help"
    echo ""
  elif [ "$CMD" == "delete" ]; then
    echo ""
    echo "Usage: solr delete [-c name] [-deleteConfig true|false] [-p port]"
    echo ""
    echo "  Deletes a core or collection depending on whether Solr is running in standalone (core) or SolrCloud"
    echo "  mode (collection). If you're deleting a collection in SolrCloud mode, the default behavior is to also"
    echo "  delete the configuration directory from Zookeeper so long as it is not being used by another collection."
    echo "  You can override this behavior by passing -deleteConfig false when running this command."
    echo ""
    echo "  -c <name>               Name of the core / collection to delete"
    echo ""
    echo "  -deleteConfig <boolean> Delete the configuration directory from Zookeeper; default is true"
    echo ""
    echo "  -p <port>               Port of a local Solr instance where you want to delete the core/collection"
    echo "                            If not specified, the script will search the local system for a running"
    echo "                            Solr instance and will use the port of the first server it finds."
    echo ""
  elif [ "$CMD" == "create_core" ]; then
    echo ""
    echo "Usage: solr create_core [-c core] [-d confdir] [-p port]"
    echo ""
    echo "  -c <core>     Name of core to create"
    echo ""
    echo "  -d <confdir>  Configuration directory to copy when creating the new core, built-in options are:"
    echo ""
    echo "      basic_configs: Minimal Solr configuration"
    echo "      data_driven_schema_configs: Managed schema with field-guessing support enabled"
    echo "      sample_techproducts_configs: Example configuration with many optional features enabled to"
    echo "         demonstrate the full power of Solr"
    echo ""
    echo "      If not specified, default is: data_driven_schema_configs"
    echo ""
    echo "      Alternatively, you can pass the path to your own configuration directory instead of using"
    echo "      one of the built-in configurations, such as: bin/solr create_core -c mycore -d /tmp/myconfig"
    echo ""
    echo "  -p <port>     Port of a local Solr instance where you want to create the new core"
    echo "                  If not specified, the script will search the local system for a running"
    echo "                  Solr instance and will use the port of the first server it finds."
    echo ""
  elif [ "$CMD" == "create_collection" ]; then
    echo ""
    echo "Usage: solr create_collection [-c collection] [-d confdir] [-n configName] [-shards #] [-replicationFactor #] [-p port]"
    echo ""
    echo "  -c <collection>         Name of collection to create"
    echo ""
    echo "  -d <confdir>            Configuration directory to copy when creating the new collection, built-in options are:"
    echo ""
    echo "      basic_configs: Minimal Solr configuration"
    echo "      data_driven_schema_configs: Managed schema with field-guessing support enabled"
    echo "      sample_techproducts_configs: Example configuration with many optional features enabled to"
    echo "         demonstrate the full power of Solr"
    echo ""
    echo "      If not specified, default is: data_driven_schema_configs"
    echo ""
    echo "      Alternatively, you can pass the path to your own configuration directory instead of using"
    echo "      one of the built-in configurations, such as: bin/solr create_collection -c mycoll -d /tmp/myconfig"
    echo ""
    echo "      By default the script will upload the specified confdir directory into Zookeeper using the same"
    echo "      name as the collection (-c) option. Alternatively, if you want to reuse an existing directory"
    echo "      or create a confdir in Zookeeper that can be shared by multiple collections, use the -n option"
    echo ""
    echo "  -n <configName>         Name the configuration directory in Zookeeper; by default, the configuration"
    echo "                            will be uploaded to Zookeeper using the collection name (-c), but if you want"
    echo "                            to use an existing directory or override the name of the configuration in"
    echo "                            Zookeeper, then use the -c option."
    echo ""
    echo "  -shards <#>             Number of shards to split the collection into; default is 1"
    echo ""
    echo "  -replicationFactor <#>  Number of copies of each document in the collection, default is 1 (no replication)"
    echo ""
    echo "  -p <port>               Port of a local Solr instance where you want to create the new collection"
    echo "                            If not specified, the script will search the local system for a running"
    echo "                            Solr instance and will use the port of the first server it finds."
    echo ""
  elif [ "$CMD" == "zk" ]; then
    print_short_zk_usage ""
    echo "         Be sure to check the Solr logs in case of errors."
    echo ""
    echo "             -z zkHost Optional Zookeeper connection string for all commands. If specified it"
    echo "                        overrides the 'ZK_HOST=...'' defined in solr.in.sh."
    echo ""
    echo "         upconfig uploads a configset from the local machine to Zookeeper. (Backcompat: -upconfig)"
    echo ""
    echo "         downconfig downloads a configset from Zookeeper to the local machine. (Backcompat: -downconfig)"
    echo ""
    echo "             -n configName   Name of the configset in Zookeeper that will be the destination of"
    echo "                             'upconfig' and the source for 'downconfig'."
    echo ""
    echo "             -d confdir      The local directory the configuration will be uploaded from for"
    echo "                             'upconfig' or downloaded to for 'downconfig'. If 'confdir' is a child of"
    echo "                             ...solr/server/solr/configsets' then the configs will be copied from/to"
    echo "                             that directory. Otherwise it is interpreted as a simple local path."
    echo ""
    echo "         cp copies files or folders to/from Zookeeper or Zokeeper -> Zookeeper"
    echo "             -r   Recursively copy <src> to <dst>. Command will fail if <src> has children and "
    echo "                        -r is not specified. Optional"
    echo ""
    echo "             <src>, <dest> : [file:][/]path/to/local/file or zk:/path/to/zk/node"
    echo "                             NOTE: <src> and <dest> may both be Zookeeper resources prefixed by 'zk:'"
    echo "             When <src> is a zk resource, <dest> may be '.'"
    echo "             If <dest> ends with '/', then <dest> will be a local folder or parent znode and the last"
    echo "             element of the <src> path will be appended unless <src> also ends in a slash. "
    echo "             <dest> may be zk:, which may be useful when using the cp -r form to backup/restore "
    echo "             the entire zk state."
    echo "             You must enclose local paths that end in a wildcard in quotes or just"
    echo "             end the local path in a slash. That is,"
    echo "             'bin/solr zk cp -r /some/dir/ zk:/ -z localhost:2181' is equivalent to"
    echo "             'bin/solr zk cp -r \"/some/dir/*\" zk:/ -z localhost:2181'"
    echo "             but 'bin/solr zk cp -r /some/dir/* zk:/ -z localhost:2181' will throw an error"
    echo ""
    echo "             here's an example of backup/restore for a ZK configuration:"
    echo "             to copy to local: 'bin/solr zk cp -r zk:/ /some/dir -z localhost:2181'"
    echo "             to restore to ZK: 'bin/solr zk cp -r /some/dir/ zk:/ -z localhost:2181'"
    echo ""
    echo "             The 'file:' prefix is stripped, thus 'file:/wherever' specifies an absolute local path and"
    echo "             'file:somewhere' specifies a relative local path. All paths on Zookeeper are absolute."
    echo ""
    echo "             Zookeeper nodes CAN have data, so moving a single file to a parent znode"
    echo "             will overlay the data on the parent Znode so specifying the trailing slash"
    echo "             can be important."
    echo ""
    echo "             Wildcards are supported when copying from local, trailing only and must be quoted."
    echo ""
    echo "         rm deletes files or folders on Zookeeper"
    echo "             -r     Recursively delete if <path> is a directory. Command will fail if <path>"
    echo "                    has children and -r is not specified. Optional"
    echo "             <path> : [zk:]/path/to/zk/node. <path> may not be the root ('/')"
    echo ""
    echo "         mv moves (renames) znodes on Zookeeper"
    echo "             <src>, <dest> : Zookeeper nodes, the 'zk:' prefix is optional."
    echo "             If <dest> ends with '/', then <dest> will be a parent znode"
    echo "             and the last element of the <src> path will be appended."
    echo "             Zookeeper nodes CAN have data, so moving a single file to a parent znode"
    echo "             will overlay the data on the parent Znode so specifying the trailing slash"
    echo "             is important."
    echo ""
    echo "         ls lists the znodes on Zookeeper"
    echo "             -r recursively descends the path listing all znodes. Optional"
    echo "             <path>: The Zookeeper path to use as the root."
    echo ""
    echo "             Only the node names are listed, not data"
    echo ""
    echo "         mkroot makes a znode on Zookeeper with no data. Can be used to make a path of arbitrary"
    echo "             depth but primarily intended to create a 'chroot'."
    echo ""
    echo "             <path>: The Zookeeper path to create. Leading slash is assumed if not present."
    echo "                     Intermediate nodes are created as needed if not present."
    echo ""
  elif [ "$CMD" == "auth" ]; then
    echo ""
    echo "Usage: solr auth enable [-type basicAuth] -credentials user:pass [-blockUnknown <true|false>] [-updateIncludeFileOnly <true|false>]"
    echo "       solr auth enable [-type basicAuth] -prompt <true|false> [-blockUnknown <true|false>] [-updateIncludeFileOnly <true|false>]"
    echo "       solr auth disable [-updateIncludeFileOnly <true|false>]"
    echo ""
    echo "  -type <type>                           The authentication mechanism to enable. Defaults to 'basicAuth'."
    echo ""
    echo "  -credentials <user:pass>               The username and password of the initial user"
    echo "                                         Note: only one of -prompt or -credentials must be provided"
    echo ""
    echo "  -prompt <true|false>                   Prompts the user to provide the credentials"
    echo "                                         Note: only one of -prompt or -credentials must be provided"
    echo ""
    echo "  -blockUnknown <true|false>             When true, this blocks out access to unauthenticated users. When not provided,"
    echo "                                         this defaults to false (i.e. unauthenticated users can access all endpoints, except the"
    echo "                                         operations like collection-edit, security-edit, core-admin-edit etc.). Check the reference"
    echo "                                         guide for Basic Authentication for more details."
    echo ""
    echo "  -updateIncludeFileOnly <true|false>    Only update the solr.in.sh or solr.in.cmd file, and skip actual enabling/disabling"
    echo "                                         authentication (i.e. don't update security.json)"
    echo ""
    echo "  -z zkHost                              Zookeeper connection string"
    echo ""
    echo "  -d <dir>                               Specify the Solr server directory"
    echo ""
    echo "  -s <dir>                               Specify the Solr home directory. This is where any credentials or authentication"
    echo "                                         configuration files (e.g. basicAuth.conf) would be placed."
    echo ""
  fi
} # end print_usage

function print_short_zk_usage() {

  if [ "$1" != "" ]; then
    echo -e "\nERROR: $1\n"
  fi

  echo "  Usage: solr zk upconfig|downconfig -d <confdir> -n <configName> [-z zkHost]"
  echo "         solr zk cp [-r] <src> <dest> [-z zkHost]"
  echo "         solr zk rm [-r] <path> [-z zkHost]"
  echo "         solr zk mv <src> <dest> [-z zkHost]"
  echo "         solr zk ls [-r] <path> [-z zkHost]"
  echo "         solr zk mkroot <path> [-z zkHost]"
  echo ""

  if [ "$1" == "" ]; then
    echo "Type bin/solr zk -help for full usage help"
  else
    exit 1
  fi
}

# used to show the script is still alive when waiting on work to complete
function spinner() {
  local pid=$1
  local delay=0.5
  local spinstr='|/-\'
  while [ "$(ps aux | awk '{print $2}' | grep -w $pid)" ]; do
      local temp=${spinstr#?}
      printf " [%c]  " "$spinstr"
      local spinstr=$temp${spinstr%"$temp"}
      sleep $delay
      printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

# given a port, find the pid for a Solr process
function solr_pid_by_port() {
  THE_PORT="$1"
  if [ -e "$SOLR_PID_DIR/solr-$THE_PORT.pid" ]; then
    PID=`cat "$SOLR_PID_DIR/solr-$THE_PORT.pid"`
    CHECK_PID=`ps auxww | awk '{print $2}' | grep -w $PID | sort -r | tr -d ' '`
    if [ "$CHECK_PID" != "" ]; then
      local solrPID=$PID
    fi
  fi
  echo "$solrPID"
}

# extract the value of the -Djetty.port parameter from a running Solr process 
function jetty_port() {
  SOLR_PID="$1"
  SOLR_PROC=`ps auxww | grep -w $SOLR_PID | grep start\.jar | grep jetty\.port`
  IFS=' ' read -a proc_args <<< "$SOLR_PROC"
  for arg in "${proc_args[@]}"
    do
      IFS='=' read -a pair <<< "$arg"
      if [ "${pair[0]}" == "-Djetty.port" ]; then
        local jetty_port="${pair[1]}"
        break
      fi
    done    
  echo "$jetty_port"
} # end jetty_port func

# run a Solr command-line tool using the SolrCLI class; 
# useful for doing cross-platform work from the command-line using Java
function run_tool() {

  "$JAVA" $SOLR_SSL_OPTS $AUTHC_OPTS $SOLR_ZK_CREDS_AND_ACLS -Dsolr.install.dir="$SOLR_TIP" \
    -Dlog4j.configuration="file:$DEFAULT_SERVER_DIR/scripts/cloud-scripts/log4j.properties" \
    -classpath "$DEFAULT_SERVER_DIR/solr-webapp/webapp/WEB-INF/lib/*:$DEFAULT_SERVER_DIR/lib/ext/*" \
    org.apache.solr.util.SolrCLI "$@"

  return $?
} # end run_tool function

# get information about any Solr nodes running on this host
function get_info() {
  CODE=4
  # first, see if Solr is running
  numSolrs=`find "$SOLR_PID_DIR" -name "solr-*.pid" -type f | wc -l | tr -d ' '`
  if [ "$numSolrs" != "0" ]; then
    echo -e "\nFound $numSolrs Solr nodes: "
    while read PIDF
      do
        ID=`cat "$PIDF"`
        port=`jetty_port "$ID"`
        if [ "$port" != "" ]; then
          echo -e "\nSolr process $ID running on port $port"
          run_tool status -solr "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$port/solr"
          CODE=$?
          echo ""
        else
          echo -e "\nSolr process $ID from $PIDF not found."
          CODE=1
        fi
    done < <(find "$SOLR_PID_DIR" -name "solr-*.pid" -type f)
  else
    # no pid files but check using ps just to be sure
    numSolrs=`ps auxww | grep start\.jar | grep solr\.solr\.home | grep -v grep | wc -l | sed -e 's/^[ \t]*//'`
    if [ "$numSolrs" != "0" ]; then
      echo -e "\nFound $numSolrs Solr nodes: "
      PROCESSES=$(ps auxww | grep start\.jar | grep solr\.solr\.home | grep -v grep | awk '{print $2}' | sort -r)
      for ID in $PROCESSES
        do
          port=`jetty_port "$ID"`
          if [ "$port" != "" ]; then
            echo ""
            echo "Solr process $ID running on port $port"
            run_tool status -solr "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$port/solr"
            CODE=$?
            echo ""
          fi
      done
    else
      echo -e "\nNo Solr nodes are running.\n"
      CODE=3
    fi
  fi

  return $CODE
} # end get_info

# tries to gracefully stop Solr using the Jetty 
# stop command and if that fails, then uses kill -9
function stop_solr() {

  DIR="$1"
  SOLR_PORT="$2"
  STOP_PORT=`expr $SOLR_PORT - 1000`
  STOP_KEY="$3"
  SOLR_PID="$4"

  if [ "$SOLR_PID" != "" ]; then
    echo -e "Sending stop command to Solr running on port $SOLR_PORT ... waiting up to $SOLR_STOP_WAIT seconds to allow Jetty process $SOLR_PID to stop gracefully."
    "$JAVA" $SOLR_SSL_OPTS $AUTHC_OPTS -jar "$DIR/start.jar" "STOP.PORT=$STOP_PORT" "STOP.KEY=$STOP_KEY" --stop || true
      (loops=0
      while true
      do
        CHECK_PID=`ps auxww | awk '{print $2}' | grep -w $SOLR_PID | sort -r | tr -d ' '`
        if [ "$CHECK_PID" != "" ]; then
          slept=$((loops * 2))
          if [ $slept -lt $SOLR_STOP_WAIT ]; then
            sleep 2
            loops=$[$loops+1]
          else
            exit # subshell!
          fi
        else
          exit # subshell!
        fi
      done) &
    spinner $!
    rm -f "$SOLR_PID_DIR/solr-$SOLR_PORT.pid"
  else
    echo -e "No Solr nodes found to stop."
    exit 0
  fi

  CHECK_PID=`ps auxww | awk '{print $2}' | grep -w $SOLR_PID | sort -r | tr -d ' '`
  if [ "$CHECK_PID" != "" ]; then
    echo -e "Solr process $SOLR_PID is still running; forcefully killing it now."
    kill -9 $SOLR_PID
    echo "Killed process $SOLR_PID"
    rm -f "$SOLR_PID_DIR/solr-$SOLR_PORT.pid"
    sleep 1
  fi

  CHECK_PID=`ps auxww | awk '{print $2}' | grep -w $SOLR_PID | sort -r | tr -d ' '`
  if [ "$CHECK_PID" != "" ]; then
    echo "ERROR: Failed to kill previous Solr Java process $SOLR_PID ... script fails."
    exit 1
  fi
} # end stop_solr

if [ $# -eq 1 ]; then
  case $1 in
    -help|-usage|-h|--help)
        print_usage ""
        exit
    ;;
    -info|-i|status)
        get_info
        exit $?
    ;;
    -version|-v|version)
        run_tool version
        exit
    ;;
  esac
fi

if [ $# -gt 0 ]; then
  # if first arg starts with a dash (and it's not -help or -info), 
  # then assume they are starting Solr, such as: solr -f
  if [[ $1 == -* ]]; then
    SCRIPT_CMD="start"
  else
    SCRIPT_CMD="$1"
    shift
  fi
else
  # no args - just show usage and exit
  print_usage ""
  exit  
fi

if [ "$SCRIPT_CMD" == "status" ]; then
  # hacky - the script hits this if the user passes additional args with the status command,
  # which is not supported but also not worth complaining about either
  get_info
  exit
fi

# assert tool
if [ "$SCRIPT_CMD" == "assert" ]; then
  run_tool assert $*
  exit $?
fi

# run a healthcheck and exit if requested
if [ "$SCRIPT_CMD" == "healthcheck" ]; then

  if [ $# -gt 0 ]; then
    while true; do  
      case "$1" in
          -c|-collection)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Collection name is required when using the $1 option!"
                exit 1
              fi
              HEALTHCHECK_COLLECTION="$2"
              shift 2
          ;;
          -z|-zkhost)          
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "ZooKeeper connection string is required when using the $1 option!"
                exit 1
              fi
              ZK_HOST="$2"
              shift 2
          ;;
          -help|-usage)
              print_usage "$SCRIPT_CMD"           
              exit 0
          ;;
          --)
              shift
              break
          ;;
          *)
              if [ "$1" != "" ]; then            
                print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
                exit 1
              else
                break # out-of-args, stop looping
              fi 
          ;;
      esac
    done
  fi
  
  if [ -z "$ZK_HOST" ]; then
    ZK_HOST=localhost:9983
  fi
  
  if [ -z "$HEALTHCHECK_COLLECTION" ]; then
    echo "collection parameter is required!"
    print_usage "healthcheck"
    exit 1  
  fi
    
  run_tool healthcheck -zkHost "$ZK_HOST" -collection "$HEALTHCHECK_COLLECTION"
    
  exit $?
fi

# create a core or collection
if [[ "$SCRIPT_CMD" == "create" || "$SCRIPT_CMD" == "create_core" || "$SCRIPT_CMD" == "create_collection" ]]; then

  CREATE_NUM_SHARDS=1
  CREATE_REPFACT=1
  FORCE=false

  if [ $# -gt 0 ]; then
    while true; do
      case "$1" in
          -c|-core|-collection)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "name is required when using the $1 option!"
                exit 1
              fi
              CREATE_NAME="$2"
              shift 2
          ;;
          -n|-confname)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Configuration name is required when using the $1 option!"
                exit 1
              fi
              CREATE_CONFNAME="$2"
              shift 2
          ;;
          -d|-confdir)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Configuration directory is required when using the $1 option!"
                exit 1
              fi
              CREATE_CONFDIR="$2"
              shift 2
          ;;
          -s|-shards)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Shard count is required when using the $1 option!"
                exit 1
              fi
              CREATE_NUM_SHARDS="$2"
              shift 2
          ;;
          -rf|-replicationFactor)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Replication factor is required when using the $1 option!"
                exit 1
              fi
              CREATE_REPFACT="$2"
              shift 2
          ;;
          -p|-port)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Solr port is required when using the $1 option!"
                exit 1
              fi
              CREATE_PORT="$2"
              shift 2
          ;;
          -force)
              FORCE=true
              shift
          ;;
          -help|-usage)
              print_usage "$SCRIPT_CMD"
              exit 0
          ;;
          --)
              shift
              break
          ;;
          *)
              if [ "$1" != "" ]; then
                print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
                exit 1
              else
                break # out-of-args, stop looping
              fi
          ;;
      esac
    done
  fi

  if [ -z "$CREATE_CONFDIR" ]; then
    CREATE_CONFDIR='data_driven_schema_configs'
  fi

  # validate the confdir arg
  if [[ ! -d "$SOLR_TIP/server/solr/configsets/$CREATE_CONFDIR" && ! -d "$CREATE_CONFDIR" ]]; then
    echo -e "\nSpecified configuration directory $CREATE_CONFDIR not found!\n"
    exit 1
  fi

  if [ -z "$CREATE_NAME" ]; then
    echo "Name (-c) argument is required!"
    print_usage "$SCRIPT_CMD"
    exit 1
  fi

  # If not defined, use the collection name for the name of the configuration in Zookeeper
  if [ -z "$CREATE_CONFNAME" ]; then
    CREATE_CONFNAME="$CREATE_NAME"
  fi

  if [ -z "$CREATE_PORT" ]; then
    for ID in `ps auxww | grep java | grep start\.jar | awk '{print $2}' | sort -r`
      do
        port=`jetty_port "$ID"`
        if [ "$port" != "" ]; then
          CREATE_PORT=$port
          break
        fi
    done
  fi

  if [ -z "$CREATE_PORT" ]; then
    echo "Failed to determine the port of a local Solr instance, cannot create $CREATE_NAME!"
    exit 1
  fi

  if [[ "$(whoami)" == "root" ]] && [[ "$FORCE" == "false" ]] ; then
    echo "WARNING: Creating cores as the root user can cause Solr to fail and is not advisable. Exiting."
    echo "         If you started Solr as root (not advisable either), force core creation by adding argument -force"
    exit 1
  fi
  if [ "$SCRIPT_CMD" == "create_core" ]; then
    run_tool create_core -name "$CREATE_NAME" -solrUrl "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$CREATE_PORT/solr" \
      -confdir "$CREATE_CONFDIR" -configsetsDir "$SOLR_TIP/server/solr/configsets"
    exit $?
  else
    run_tool "$SCRIPT_CMD" -name "$CREATE_NAME" -solrUrl "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$CREATE_PORT/solr" \
      -shards "$CREATE_NUM_SHARDS" -replicationFactor "$CREATE_REPFACT" \
      -confname "$CREATE_CONFNAME" -confdir "$CREATE_CONFDIR" \
      -configsetsDir "$SOLR_TIP/server/solr/configsets"
    exit $?
  fi
fi

# delete a core or collection
if [[ "$SCRIPT_CMD" == "delete" ]]; then

  if [ $# -gt 0 ]; then
    while true; do
      case "$1" in
          -c|-core|-collection)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "name is required when using the $1 option!"
                exit 1
              fi
              DELETE_NAME="$2"
              shift 2
          ;;
          -p|-port)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "Solr port is required when using the $1 option!"
                exit 1
              fi
              DELETE_PORT="$2"
              shift 2
          ;;
          -deleteConfig)
              if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
                print_usage "$SCRIPT_CMD" "true|false is required when using the $1 option!"
                exit 1
              fi
              DELETE_CONFIG="$2"
              shift 2
          ;;
          -help|-usage)
              print_usage "$SCRIPT_CMD"
              exit 0
          ;;
          --)
              shift
              break
          ;;
          *)
              if [ "$1" != "" ]; then
                print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
                exit 1
              else
                break # out-of-args, stop looping
              fi
          ;;
      esac
    done
  fi

  if [ -z "$DELETE_NAME" ]; then
    echo "Name (-c) argument is required!"
    print_usage "$SCRIPT_CMD"
    exit 1
  fi

  # If not defined, use the collection name for the name of the configuration in Zookeeper
  if [ -z "$DELETE_CONFIG" ]; then
    DELETE_CONFIG=true
  fi

  if [ -z "$DELETE_PORT" ]; then
    for ID in `ps auxww | grep java | grep start\.jar | awk '{print $2}' | sort -r`
      do
        port=`jetty_port "$ID"`
        if [ "$port" != "" ]; then
          DELETE_PORT=$port
          break
        fi
    done
  fi

  if [ -z "$DELETE_PORT" ]; then
    echo "Failed to determine the port of a local Solr instance, cannot delete $DELETE_NAME!"
    exit 1
  fi

  run_tool delete -name "$DELETE_NAME" -deleteConfig "$DELETE_CONFIG" \
    -solrUrl "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$DELETE_PORT/solr"
  exit $?
fi

ZK_RECURSE=false
# Zookeeper file maintenance (upconfig, downconfig, files up/down etc.)
# It's a little clumsy to have the parsing go round and round for upconfig and downconfig, but that's
# necessary for back-compat
if [[ "$SCRIPT_CMD" == "zk" ]]; then

  if [ $# -gt 0 ]; then
    while true; do
      case "$1" in
        -upconfig|upconfig|-downconfig|downconfig|cp|rm|mv|ls|mkroot)
            if [ "${1:0:1}" == "-" ]; then
              ZK_OP=${1:1}
            else
              ZK_OP=$1
            fi
            shift 1
        ;;
        -z|-zkhost)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_short_zk_usage "$SCRIPT_CMD" "ZooKeeper connection string is required when using the $1 option!"
            fi
            ZK_HOST="$2"
            shift 2
        ;;
        -n|-confname)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_short_zk_usage "$SCRIPT_CMD" "Configuration name is required when using the $1 option!"
            fi
            CONFIGSET_CONFNAME="$2"
            shift 2
        ;;
        -d|-confdir)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_short_zk_usage "$SCRIPT_CMD" "Configuration directory is required when using the $1 option!"
            fi
            CONFIGSET_CONFDIR="$2"
            shift 2
        ;;
        -r)
            ZK_RECURSE="true"
            shift
        ;;
        -help|-usage|-h)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)  # Pick up <src> <dst> or <path> params for rm, ls, cp, mv, mkroot.
            if [ "$1" == "" ]; then
              break # out-of-args, stop looping
            fi
            if [ -z "$ZK_SRC" ]; then
              ZK_SRC=$1
            else
              if [ -z "$ZK_DST" ]; then
                ZK_DST=$1
              else
                print_short_zk_usage "Unrecognized or misplaced command $1. 'cp' with trailing asterisk requires quoting, see help text."
              fi
            fi
            shift
        ;;
      esac
    done
  fi

  if [ -z "$ZK_OP" ]; then
    print_short_zk_usage "Zookeeper operation (one of 'upconfig', 'downconfig', 'rm', 'mv', 'cp', 'ls', 'mkroot') is required!"
  fi

  if [ -z "$ZK_HOST" ]; then
    print_short_zk_usage "Zookeeper address (-z) argument is required or ZK_HOST must be specified in the solr.in.sh file."
  fi

  if [[ "$ZK_OP" == "upconfig" ||  "$ZK_OP" == "downconfig" ]]; then
    if [ -z "$CONFIGSET_CONFDIR" ]; then
      print_short_zk_usage "Local directory of the configset (-d) argument is required!"
    fi

    if [ -z "$CONFIGSET_CONFNAME" ]; then
      print_short_zk_usage "Configset name on Zookeeper (-n) argument is required!"
    fi
  fi

  if [[ "$ZK_OP" == "cp" || "$ZK_OP" == "mv" ]]; then
    if [[ -z "$ZK_SRC" || -z "$ZK_DST" ]]; then
      print_short_zk_usage "<source> and <destination> must be specified when using either the 'mv' or 'cp' commands."
    fi
    if [[ "$ZK_OP" == "cp" && "${ZK_SRC:0:3}" != "zk:" && "${ZK_DST:0:3}" != "zk:" ]]; then
      print_short_zk_usage "One of the source or desintation paths must be prefixed by 'zk:' for the 'cp' command."
    fi
  fi

  if [[ "$ZK_OP" == "mkroot" ]]; then
    if [[ -z "$ZK_SRC" ]]; then
      print_short_zk_usage "<path> must be specified when using the 'mkroot' command."
    fi
  fi


  case "$ZK_OP" in
    upconfig)
      run_tool "$ZK_OP" -confname "$CONFIGSET_CONFNAME" -confdir "$CONFIGSET_CONFDIR" -zkHost "$ZK_HOST" -configsetsDir "$SOLR_TIP/server/solr/configsets"
    ;;
    downconfig)
      run_tool "$ZK_OP" -confname "$CONFIGSET_CONFNAME" -confdir "$CONFIGSET_CONFDIR" -zkHost "$ZK_HOST"
    ;;
    rm)
      if [ -z "$ZK_SRC" ]; then
        print_short_zk_usage "Zookeeper path to remove must be specified when using the 'rm' command"
      fi
      run_tool "$ZK_OP" -path "$ZK_SRC" -zkHost "$ZK_HOST" -recurse "$ZK_RECURSE"
    ;;
    mv)
      run_tool "$ZK_OP" -src "$ZK_SRC" -dst "$ZK_DST" -zkHost "$ZK_HOST"
    ;;
    cp)
      run_tool "$ZK_OP" -src "$ZK_SRC" -dst "$ZK_DST" -zkHost "$ZK_HOST" -recurse "$ZK_RECURSE"
    ;;
    ls)
      if [ -z "$ZK_SRC" ]; then
        print_short_zk_usage "Zookeeper path to list must be specified when using the 'ls' command"
      fi
      run_tool "$ZK_OP" -path "$ZK_SRC" -recurse "$ZK_RECURSE" -zkHost "$ZK_HOST"
    ;;
    mkroot)
      if [ -z "$ZK_SRC" ]; then
        print_short_zk_usage "Zookeeper path to list must be specified when using the 'mkroot' command"
      fi
      run_tool "$ZK_OP" -path "$ZK_SRC" -zkHost "$ZK_HOST"
    ;;
    *)
      print_short_zk_usage "Unrecognized Zookeeper operation $ZK_OP"
    ;;
  esac

  exit $?
fi

if [[ "$SCRIPT_CMD" == "auth" ]]; then
  declare -a AUTH_PARAMS
  if [ $# -gt 0 ]; then
    while true; do
      case "$1" in
        enable|disable)
            AUTH_OP=$1
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "$AUTH_OP")
            shift
        ;;
        -z|-zkhost|zkHost)
            ZK_HOST="$2"
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-zkHost" "$ZK_HOST")
            shift 2
        ;;
        -t|-type)
            AUTH_TYPE="$2"
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-type" "$AUTH_TYPE")
            shift 2
        ;;
        -credentials)
            AUTH_CREDENTIALS="$2"
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-credentials" "$AUTH_CREDENTIALS")
            shift 2
        ;;
        -solrIncludeFile)
            SOLR_INCLUDE="$2"
            shift 2
        ;;
        -prompt)
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-prompt" "$2")
            shift
        ;;
        -blockUnknown)
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-blockUnknown" "$2")
            shift
            break
        ;;
        -updateIncludeFileOnly)
            AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-updateIncludeFileOnly" "$2")
            shift
            break
        ;;
        -d|-dir)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Server directory is required when using the $1 option!"
              exit 1
            fi

            if [[ "$2" == "." || "$2" == "./" || "$2" == ".." || "$2" == "../" ]]; then
              SOLR_SERVER_DIR="$(pwd)/$2"
            else
              # see if the arg value is relative to the tip vs full path
              if [[ "$2" != /* ]] && [[ -d "$SOLR_TIP/$2" ]]; then
                SOLR_SERVER_DIR="$SOLR_TIP/$2"
              else
                SOLR_SERVER_DIR="$2"
              fi
            fi
            # resolve it to an absolute path
            SOLR_SERVER_DIR="$(cd "$SOLR_SERVER_DIR"; pwd)"
            shift 2
        ;;
        -s|-solr.home)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Solr home directory is required when using the $1 option!"
              exit 1
            fi

            SOLR_HOME="$2"
            shift 2
        ;;
        -help|-usage|-h)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)
            shift
            break
        ;;
      esac
    done
  fi

  if [ -z "$SOLR_SERVER_DIR" ]; then
    SOLR_SERVER_DIR="$DEFAULT_SERVER_DIR"
  fi
  if [ ! -e "$SOLR_SERVER_DIR" ]; then
    echo -e "\nSolr server directory $SOLR_SERVER_DIR not found!\n"
    exit 1
  fi
  if [ -z "$SOLR_HOME" ]; then
    SOLR_HOME="$SOLR_SERVER_DIR/solr"
  else
    if [[ $SOLR_HOME != /* ]] && [[ -d "$SOLR_SERVER_DIR/$SOLR_HOME" ]]; then
      SOLR_HOME="$SOLR_SERVER_DIR/$SOLR_HOME"
      SOLR_PID_DIR="$SOLR_HOME"
    elif [[ $SOLR_HOME != /* ]] && [[ -d "`pwd`/$SOLR_HOME" ]]; then
      SOLR_HOME="$(pwd)/$SOLR_HOME"
    fi
  fi

  if [ -z "$AUTH_OP" ]; then
    print_usage "$SCRIPT_CMD"
    exit 0
  fi

  AUTH_PARAMS=("${AUTH_PARAMS[@]}" "-solrIncludeFile" "$SOLR_INCLUDE")

  if [ -z "$AUTH_PORT" ]; then
    for ID in `ps auxww | grep java | grep start\.jar | awk '{print $2}' | sort -r`
      do
        port=`jetty_port "$ID"`
        if [ "$port" != "" ]; then
          AUTH_PORT=$port
          break
        fi
      done
  fi
  run_tool auth ${AUTH_PARAMS[@]} -solrUrl "$SOLR_URL_SCHEME://$SOLR_TOOL_HOST:$AUTH_PORT/solr" -authConfDir "$SOLR_HOME"
  exit $?
fi


# verify the command given is supported
if [ "$SCRIPT_CMD" != "stop" ] && [ "$SCRIPT_CMD" != "start" ] && [ "$SCRIPT_CMD" != "restart" ] && [ "$SCRIPT_CMD" != "status" ] && [ "$SCRIPT_CMD" != "assert" ]; then
  print_usage "" "$SCRIPT_CMD is not a valid command!"
  exit 1
fi

# Run in foreground (default is to run in the background)
FG="false"
FORCE=false
noprompt=false
SOLR_OPTS=($SOLR_OPTS)
PASS_TO_RUN_EXAMPLE=

if [ $# -gt 0 ]; then
  while true; do  
    case "$1" in
        -c|-cloud)
            SOLR_MODE="solrcloud"
            PASS_TO_RUN_EXAMPLE+=" -c"
            shift
        ;;
        -d|-dir)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Server directory is required when using the $1 option!"
              exit 1
            fi

            if [[ "$2" == "." || "$2" == "./" || "$2" == ".." || "$2" == "../" ]]; then
              SOLR_SERVER_DIR="$(pwd)/$2"
            else
              # see if the arg value is relative to the tip vs full path
              if [[ "$2" != /* ]] && [[ -d "$SOLR_TIP/$2" ]]; then
                SOLR_SERVER_DIR="$SOLR_TIP/$2"
              else
                SOLR_SERVER_DIR="$2"
              fi
            fi
            # resolve it to an absolute path
            SOLR_SERVER_DIR="$(cd "$SOLR_SERVER_DIR"; pwd)"
            shift 2
        ;;
        -s|-solr.home)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Solr home directory is required when using the $1 option!"
              exit 1
            fi

            SOLR_HOME="$2"
            shift 2
        ;;
        -e|-example)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Example name is required when using the $1 option!"
              exit 1
            fi
            EXAMPLE="$2"
            shift 2
        ;;
        -f|-foreground)
            FG="true"
            shift
        ;;
        -h|-host)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Hostname is required when using the $1 option!"
              exit 1
            fi
            SOLR_HOST="$2"
            PASS_TO_RUN_EXAMPLE+=" -h $SOLR_HOST"
            shift 2
        ;;
        -m|-memory)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Memory setting is required when using the $1 option!"
              exit 1
            fi
            SOLR_HEAP="$2"
            PASS_TO_RUN_EXAMPLE+=" -m $SOLR_HEAP"
            shift 2
        ;;
        -p|-port)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Port number is required when using the $1 option!"
              exit 1
            fi
            SOLR_PORT="$2"
            PASS_TO_RUN_EXAMPLE+=" -p $SOLR_PORT"
            shift 2
        ;;
        -z|-zkhost)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Zookeeper connection string is required when using the $1 option!"
              exit 1
            fi
            ZK_HOST="$2"
            SOLR_MODE="solrcloud"
            PASS_TO_RUN_EXAMPLE+=" -z $ZK_HOST"
            shift 2
        ;;
        -a|-addlopts)
            ADDITIONAL_CMD_OPTS="$2"
            PASS_TO_RUN_EXAMPLE+=" -a \"$ADDITIONAL_CMD_OPTS\""
            shift 2
        ;;
        -k|-key)
            STOP_KEY="$2"
            shift 2
        ;;
        -help|-usage)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        -noprompt)
            noprompt=true
            PASS_TO_RUN_EXAMPLE+=" -noprompt"
            shift
        ;;
        -V|-verbose)
            verbose=true
            PASS_TO_RUN_EXAMPLE+=" --verbose"
            shift
        ;;
        -v)
            SOLR_LOG_LEVEL=DEBUG
            shift
        ;;
        -q)
            SOLR_LOG_LEVEL=WARN
            shift
        ;;
        -all)
            stop_all=true
            shift
        ;;
        -force)
            FORCE=true
            shift
        ;;
        --)
            shift
            break
        ;;
        *)
            if [ "${1:0:2}" == "-D" ]; then
              # pass thru any opts that begin with -D (java system props)
              SOLR_OPTS+=("$1")
              PASS_TO_RUN_EXAMPLE+=" $1"
              shift
            else
              if [ "$1" != "" ]; then
                print_usage "$SCRIPT_CMD" "$1 is not supported by this script"
                exit 1
              else
                break # out-of-args, stop looping
              fi
            fi
        ;;
    esac
  done
fi

if [[ $SOLR_LOG_LEVEL ]] ; then
  SOLR_LOG_LEVEL_OPT="-Dsolr.log.level=$SOLR_LOG_LEVEL"
fi

if [ -z "$SOLR_SERVER_DIR" ]; then
  SOLR_SERVER_DIR="$DEFAULT_SERVER_DIR"
fi

if [ ! -e "$SOLR_SERVER_DIR" ]; then
  echo -e "\nSolr server directory $SOLR_SERVER_DIR not found!\n"
  exit 1
fi

if [[ "$FG" == 'true' && "$EXAMPLE" != "" ]]; then
  FG='false'
  echo -e "\nWARNING: Foreground mode (-f) not supported when running examples.\n"
fi

#
# If the user specified an example to run, invoke the run_example tool (Java app) and exit
# otherwise let this script proceed to process the user request
#
if [ -n "$EXAMPLE" ] && [ "$SCRIPT_CMD" == "start" ]; then
  run_tool run_example -e $EXAMPLE -d "$SOLR_SERVER_DIR" -urlScheme $SOLR_URL_SCHEME $PASS_TO_RUN_EXAMPLE
  exit $?
fi

############# start/stop logic below here ################

if $verbose ; then
  echo "Using Solr root directory: $SOLR_TIP"
  echo "Using Java: $JAVA"
  "$JAVA" -version
fi

if [ "$SOLR_HOST" != "" ]; then
  SOLR_HOST_ARG=("-Dhost=$SOLR_HOST")
else
  SOLR_HOST_ARG=()
fi

if [ -z "$STOP_KEY" ]; then
  STOP_KEY='solrrocks'
fi

# stop all if no port specified
if [[ "$SCRIPT_CMD" == "stop" && -z "$SOLR_PORT" ]]; then
  if $stop_all; then
    none_stopped=true
    find "$SOLR_PID_DIR" -name "solr-*.pid" -type f | while read PIDF
      do
        NEXT_PID=`cat "$PIDF"`
        port=`jetty_port "$NEXT_PID"`
        if [ "$port" != "" ]; then
          stop_solr "$SOLR_SERVER_DIR" "$port" "$STOP_KEY" "$NEXT_PID"
          none_stopped=false
        fi
        rm -f "$PIDF"
    done
    # TODO: none_stopped doesn't get reflected across the subshell
    # This can be uncommented once we find a clean way out of it
    # if $none_stopped; then
    #   echo -e "\nNo Solr nodes found to stop.\n"
    # fi
  else
    # not stopping all and don't have a port, but if we can find the pid file for the default port 8983, then use that
    none_stopped=true
    numSolrs=`find "$SOLR_PID_DIR" -name "solr-*.pid" -type f | wc -l | tr -d ' '`
    if [ $numSolrs -eq 1 ]; then
      # only do this if there is only 1 node running, otherwise they must provide the -p or -all
      PID="$(cat "$(find "$SOLR_PID_DIR" -name "solr-*.pid" -type f)")"
      CHECK_PID=`ps auxww | awk '{print $2}' | grep -w $PID | sort -r | tr -d ' '`
      if [ "$CHECK_PID" != "" ]; then
        port=`jetty_port "$CHECK_PID"`
        if [ "$port" != "" ]; then
          stop_solr "$SOLR_SERVER_DIR" "$port" "$STOP_KEY" "$CHECK_PID"
          none_stopped=false
        fi
      fi
    fi

    if $none_stopped; then
      if [ $numSolrs -gt 0 ]; then
        echo -e "\nFound $numSolrs Solr nodes running! Must either specify a port using -p or -all to stop all Solr nodes on this host.\n"
      else
        echo -e "\nNo Solr nodes found to stop.\n"
      fi
      exit 1
    fi
  fi
  exit
fi

if [ -z "$SOLR_PORT" ]; then
  SOLR_PORT=8983
fi

if [ -z "$STOP_PORT" ]; then
  STOP_PORT=`expr $SOLR_PORT - 1000`
fi

if [ "$SCRIPT_CMD" == "start" ] || [ "$SCRIPT_CMD" == "restart" ] ; then
  if [[ "$(whoami)" == "root" ]] && [[ "$FORCE" == "false" ]] ; then
    echo "WARNING: Starting Solr as the root user is a security risk and not considered best practice. Exiting."
    echo "         Please consult the Reference Guide. To override this check, start with argument '-force'"
    exit 1
  fi
fi

if [[ "$SCRIPT_CMD" == "start" ]]; then
  # see if Solr is already running
  SOLR_PID=`solr_pid_by_port "$SOLR_PORT"`

  if [ -z "$SOLR_PID" ]; then
    # not found using the pid file ... but use ps to ensure not found
    SOLR_PID=`ps auxww | grep start\.jar | grep -w "\-Djetty\.port=$SOLR_PORT" | grep -v grep | awk '{print $2}' | sort -r`
  fi

  if [ "$SOLR_PID" != "" ]; then
    echo -e "\nPort $SOLR_PORT is already being used by another process (pid: $SOLR_PID)\nPlease choose a different port using the -p option.\n"
    exit 1
  fi
else
  # either stop or restart
  # see if Solr is already running
  SOLR_PID=`solr_pid_by_port "$SOLR_PORT"`
  if [ -z "$SOLR_PID" ]; then
    # not found using the pid file ... but use ps to ensure not found
    SOLR_PID=`ps auxww | grep start\.jar | grep -w "\-Djetty\.port=$SOLR_PORT" | grep -v grep | awk '{print $2}' | sort -r`
  fi
  if [ "$SOLR_PID" != "" ]; then
    stop_solr "$SOLR_SERVER_DIR" "$SOLR_PORT" "$STOP_KEY" "$SOLR_PID"
  else
    if [ "$SCRIPT_CMD" == "stop" ]; then
      echo -e "No process found for Solr node running on port $SOLR_PORT"
      exit 1
    fi
  fi
fi

if [ -z "$SOLR_HOME" ]; then
  SOLR_HOME="$SOLR_SERVER_DIR/solr"
else
  if [[ $SOLR_HOME != /* ]] && [[ -d "$SOLR_SERVER_DIR/$SOLR_HOME" ]]; then
    SOLR_HOME="$SOLR_SERVER_DIR/$SOLR_HOME"
    SOLR_PID_DIR="$SOLR_HOME"
  elif [[ $SOLR_HOME != /* ]] && [[ -d "`pwd`/$SOLR_HOME" ]]; then
    SOLR_HOME="$(pwd)/$SOLR_HOME"
  fi
fi

# This is quite hacky, but examples rely on a different log4j.properties
# so that we can write logs for examples to $SOLR_HOME/../logs
if [ -z "$SOLR_LOGS_DIR" ]; then
  SOLR_LOGS_DIR="$SOLR_SERVER_DIR/logs"
fi
EXAMPLE_DIR="$SOLR_TIP/example"
if [ "${SOLR_HOME:0:${#EXAMPLE_DIR}}" = "$EXAMPLE_DIR" ]; then
  LOG4J_PROPS="$EXAMPLE_DIR/resources/log4j.properties"
  SOLR_LOGS_DIR="$SOLR_HOME/../logs"
fi

LOG4J_CONFIG=()
if [ -n "$LOG4J_PROPS" ]; then
  LOG4J_CONFIG+=("-Dlog4j.configuration=file:$LOG4J_PROPS")
fi

if [ "$SCRIPT_CMD" == "stop" ]; then
  # already stopped, script is done.
  exit 0
fi

# NOTE: If the script gets to here, then it is starting up a Solr node.

if [ ! -e "$SOLR_HOME" ]; then
  echo -e "\nSolr home directory $SOLR_HOME not found!\n"
  exit 1
fi
if $verbose ; then
  q=""
else
  q="-q"
fi
if [ "${SOLR_LOG_PRESTART_ROTATION:=true}" == "true" ]; then
  run_tool utils -s "$DEFAULT_SERVER_DIR" -l "$SOLR_LOGS_DIR" $q -remove_old_solr_logs 7 || echo "Failed removing old solr logs"
  run_tool utils -s "$DEFAULT_SERVER_DIR" -l "$SOLR_LOGS_DIR" $q -archive_gc_logs $q     || echo "Failed archiving old GC logs"
  run_tool utils -s "$DEFAULT_SERVER_DIR" -l "$SOLR_LOGS_DIR" $q -archive_console_logs   || echo "Failed archiving old console logs"
  run_tool utils -s "$DEFAULT_SERVER_DIR" -l "$SOLR_LOGS_DIR" $q -rotate_solr_logs 9     || echo "Failed rotating old solr logs"
fi

# Establish default GC logging opts if no env var set (otherwise init to sensible default)
if [ -z ${GC_LOG_OPTS+x} ]; then
  if [[ "$JAVA_VER_NUM" < "9" ]] ; then
    GC_LOG_OPTS=('-verbose:gc' '-XX:+PrintHeapAtGC' '-XX:+PrintGCDetails' \
                 '-XX:+PrintGCDateStamps' '-XX:+PrintGCTimeStamps' '-XX:+PrintTenuringDistribution' \
                 '-XX:+PrintGCApplicationStoppedTime')
  else
    GC_LOG_OPTS=('-Xlog:gc*')
  fi
else
  GC_LOG_OPTS=($GC_LOG_OPTS)
fi

# if verbose gc logging enabled, setup the location of the log file and rotation
if [ "$GC_LOG_OPTS" != "" ]; then
  if [[ "$JAVA_VER_NUM" < "9" ]] ; then
    gc_log_flag="-Xloggc"
    if [ "$JAVA_VENDOR" == "IBM J9" ]; then
      gc_log_flag="-Xverbosegclog"
    fi
    GC_LOG_OPTS+=("$gc_log_flag:$SOLR_LOGS_DIR/solr_gc.log" '-XX:+UseGCLogFileRotation' '-XX:NumberOfGCLogFiles=9' '-XX:GCLogFileSize=20M')
  else
    # http://openjdk.java.net/jeps/158
    for i in "${!GC_LOG_OPTS[@]}";
    do
      # for simplicity, we only look at the prefix '-Xlog:gc'
      # (if 'all' or multiple tags are used starting with anything other then 'gc' the user is on their own)
      # if a single additional ':' exists in param, then there is already an explicit output specifier
      GC_LOG_OPTS[$i]=$(echo ${GC_LOG_OPTS[$i]} | sed "s|^\(-Xlog:gc[^:]*$\)|\1:file=$SOLR_LOGS_DIR/solr_gc.log:time,uptime:filecount=9,filesize=20000|")
    done
  fi
fi

# If ZK_HOST is defined, the assume SolrCloud mode
if [[ -n "$ZK_HOST" ]]; then
  SOLR_MODE="solrcloud"
fi

if [ "$SOLR_MODE" == 'solrcloud' ]; then
  if [ -z "$ZK_CLIENT_TIMEOUT" ]; then
    ZK_CLIENT_TIMEOUT="15000"
  fi
  
  CLOUD_MODE_OPTS=("-DzkClientTimeout=$ZK_CLIENT_TIMEOUT")
  
  if [ "$ZK_HOST" != "" ]; then
    CLOUD_MODE_OPTS+=("-DzkHost=$ZK_HOST")
  else
    if $verbose ; then
      echo "Configuring SolrCloud to launch an embedded Zookeeper using -DzkRun"
    fi

    CLOUD_MODE_OPTS+=('-DzkRun')
  fi

  # and if collection1 needs to be bootstrapped
  if [ -e "$SOLR_HOME/collection1/core.properties" ]; then
    CLOUD_MODE_OPTS+=('-Dbootstrap_confdir=./solr/collection1/conf' '-Dcollection.configName=myconf' '-DnumShards=1')
  fi
    
else
  if [ ! -e "$SOLR_HOME/solr.xml" ]; then
    echo -e "\nSolr home directory $SOLR_HOME must contain a solr.xml file!\n"
    exit 1
  fi
fi

# These are useful for attaching remote profilers like VisualVM/JConsole
if [ "$ENABLE_REMOTE_JMX_OPTS" == "true" ]; then

  if [ -z "$RMI_PORT" ]; then
    RMI_PORT=`expr $SOLR_PORT + 10000`
    if [ $RMI_PORT -gt 65535 ]; then
      echo -e "\nRMI_PORT is $RMI_PORT, which is invalid!\n"
      exit 1
    fi
  fi

  REMOTE_JMX_OPTS=('-Dcom.sun.management.jmxremote' \
    '-Dcom.sun.management.jmxremote.local.only=false' \
    '-Dcom.sun.management.jmxremote.ssl=false' \
    '-Dcom.sun.management.jmxremote.authenticate=false' \
    "-Dcom.sun.management.jmxremote.port=$RMI_PORT" \
    "-Dcom.sun.management.jmxremote.rmi.port=$RMI_PORT")

  # if the host is set, then set that as the rmi server hostname
  if [ "$SOLR_HOST" != "" ]; then
    REMOTE_JMX_OPTS+=("-Djava.rmi.server.hostname=$SOLR_HOST")
  fi
else
  REMOTE_JMX_OPTS=()
fi

JAVA_MEM_OPTS=()
if [ -z "$SOLR_HEAP" ] && [ -n "$SOLR_JAVA_MEM" ]; then
  JAVA_MEM_OPTS=($SOLR_JAVA_MEM)
else
  SOLR_HEAP="${SOLR_HEAP:-512m}"
  JAVA_MEM_OPTS=("-Xms$SOLR_HEAP" "-Xmx$SOLR_HEAP")
fi

# Pick default for Java thread stack size, and then add to SOLR_OPTS
if [ -z ${SOLR_JAVA_STACK_SIZE+x} ]; then
  SOLR_JAVA_STACK_SIZE='-Xss256k'
fi
SOLR_OPTS+=($SOLR_JAVA_STACK_SIZE)

if [ -z "$SOLR_TIMEZONE" ]; then
  SOLR_TIMEZONE='UTC'
fi

# Launches Solr in foreground/background depending on parameters
function launch_solr() {

  run_in_foreground="$1"
  stop_port="$STOP_PORT"
  
  SOLR_ADDL_ARGS="$2"

  # define default GC_TUNE
  if [ -z ${GC_TUNE+x} ]; then
      GC_TUNE=('-XX:NewRatio=3' \
        '-XX:SurvivorRatio=4' \
        '-XX:TargetSurvivorRatio=90' \
        '-XX:MaxTenuringThreshold=8' \
        '-XX:+UseConcMarkSweepGC' \
        '-XX:+UseParNewGC' \
        '-XX:ConcGCThreads=4' '-XX:ParallelGCThreads=4' \
        '-XX:+CMSScavengeBeforeRemark' \
        '-XX:PretenureSizeThreshold=64m' \
        '-XX:+UseCMSInitiatingOccupancyOnly' \
        '-XX:CMSInitiatingOccupancyFraction=50' \
        '-XX:CMSMaxAbortablePrecleanTime=6000' \
        '-XX:+CMSParallelRemarkEnabled' \
        '-XX:+ParallelRefProcEnabled' \
        '-XX:-OmitStackTraceInFastThrow')
  else
    GC_TUNE=($GC_TUNE)
  fi


  # If SSL-related system props are set, add them to SOLR_OPTS
  if [ -n "$SOLR_SSL_OPTS" ]; then
    # If using SSL and solr.jetty.https.port not set explicitly, use the jetty.port
    SSL_PORT_PROP="-Dsolr.jetty.https.port=$SOLR_PORT"
    SOLR_OPTS+=($SOLR_SSL_OPTS "$SSL_PORT_PROP")
  fi

  # If authentication system props are set, add them to SOLR_OPTS
  if [ -n "$AUTHC_OPTS" ]; then
    SOLR_OPTS+=($AUTHC_OPTS)
  fi

  if $verbose ; then
    echo -e "\nStarting Solr using the following settings:"
    echo -e "    JAVA            = $JAVA"
    echo -e "    SOLR_SERVER_DIR = $SOLR_SERVER_DIR"
    echo -e "    SOLR_HOME       = $SOLR_HOME"
    echo -e "    SOLR_HOST       = $SOLR_HOST"
    echo -e "    SOLR_PORT       = $SOLR_PORT"
    echo -e "    STOP_PORT       = $STOP_PORT"
    echo -e "    JAVA_MEM_OPTS   = ${JAVA_MEM_OPTS[@]}"
    echo -e "    GC_TUNE         = ${GC_TUNE[@]}"
    echo -e "    GC_LOG_OPTS     = ${GC_LOG_OPTS[@]}"
    echo -e "    SOLR_TIMEZONE   = $SOLR_TIMEZONE"

    if [ "$SOLR_MODE" == "solrcloud" ]; then
      echo -e "    CLOUD_MODE_OPTS = ${CLOUD_MODE_OPTS[@]}"
    fi

    if [ "$SOLR_OPTS" != "" ]; then
      echo -e "    SOLR_OPTS       = ${SOLR_OPTS[@]}"
    fi

    if [ "$SOLR_ADDL_ARGS" != "" ]; then
      echo -e "    SOLR_ADDL_ARGS  = $SOLR_ADDL_ARGS"
    fi

    if [ "$ENABLE_REMOTE_JMX_OPTS" == "true" ]; then
      echo -e "    RMI_PORT        = $RMI_PORT"
      echo -e "    REMOTE_JMX_OPTS = ${REMOTE_JMX_OPTS[@]}"
    fi

    if [ "$SOLR_LOG_LEVEL" != "" ]; then
      echo -e "    SOLR_LOG_LEVEL  = $SOLR_LOG_LEVEL"
    fi

    echo -e "\n"
  fi
    
  # need to launch solr from the server dir
  cd "$SOLR_SERVER_DIR"
  
  if [ ! -e "$SOLR_SERVER_DIR/start.jar" ]; then
    echo -e "\nERROR: start.jar file not found in $SOLR_SERVER_DIR!\nPlease check your -d parameter to set the correct Solr server directory.\n"
    exit 1
  fi

  SOLR_START_OPTS=('-server' "${JAVA_MEM_OPTS[@]}" "${GC_TUNE[@]}" "${GC_LOG_OPTS[@]}" \
    "${REMOTE_JMX_OPTS[@]}" "${CLOUD_MODE_OPTS[@]}" $SOLR_LOG_LEVEL_OPT -Dsolr.log.dir="$SOLR_LOGS_DIR" \
    "-Djetty.port=$SOLR_PORT" "-DSTOP.PORT=$stop_port" "-DSTOP.KEY=$STOP_KEY" \
    "${SOLR_HOST_ARG[@]}" "-Duser.timezone=$SOLR_TIMEZONE" \
    "-Djetty.home=$SOLR_SERVER_DIR" "-Dsolr.solr.home=$SOLR_HOME" "-Dsolr.install.dir=$SOLR_TIP" \
    "${LOG4J_CONFIG[@]}" "${SOLR_OPTS[@]}")

  if [ "$SOLR_MODE" == "solrcloud" ]; then
    IN_CLOUD_MODE=" in SolrCloud mode"
  fi

  mkdir -p "$SOLR_LOGS_DIR" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo -e "\nERROR: Logs directory $SOLR_LOGS_DIR could not be created. Exiting"
    exit 1
  fi
  if [ ! -w "$SOLR_LOGS_DIR" ]; then
    echo -e "\nERROR: Logs directory $SOLR_LOGS_DIR is not writable. Exiting"
    exit 1
  fi
  case "$SOLR_LOGS_DIR" in
    contexts|etc|lib|modules|resources|scripts|solr|solr-webapp)
      echo -e "\nERROR: Logs directory $SOLR_LOGS_DIR is invalid. Reserved for the system. Exiting"
      exit 1
      ;;
  esac

  if [ "$run_in_foreground" == "true" ]; then
    exec "$JAVA" "${SOLR_START_OPTS[@]}" $SOLR_ADDL_ARGS -jar start.jar "${SOLR_JETTY_CONFIG[@]}"
  else
    # run Solr in the background
    nohup "$JAVA" "${SOLR_START_OPTS[@]}" $SOLR_ADDL_ARGS -Dsolr.log.muteconsole \
	"-XX:OnOutOfMemoryError=$SOLR_TIP/bin/oom_solr.sh $SOLR_PORT $SOLR_LOGS_DIR" \
        -jar start.jar "${SOLR_JETTY_CONFIG[@]}" \
	1>"$SOLR_LOGS_DIR/solr-$SOLR_PORT-console.log" 2>&1 & echo $! > "$SOLR_PID_DIR/solr-$SOLR_PORT.pid"

    # check if /proc/sys/kernel/random/entropy_avail exists then check output of cat /proc/sys/kernel/random/entropy_avail to see if less than 300
    if [[ -f /proc/sys/kernel/random/entropy_avail ]] && (( `cat /proc/sys/kernel/random/entropy_avail` < 300)); then
	echo "Warning: Available entropy is low. As a result, use of the UUIDField, SSL, or any other features that require"
	echo "RNG might not work properly. To check for the amount of available entropy, use 'cat /proc/sys/kernel/random/entropy_avail'."
	echo ""
    fi
    # no lsof on cygwin though
    if hash lsof 2>/dev/null ; then  # hash returns true if lsof is on the path
      echo -n "Waiting up to $SOLR_STOP_WAIT seconds to see Solr running on port $SOLR_PORT"
      # Launch in a subshell to show the spinner
      (loops=0
      while true
      do
        running=`lsof -PniTCP:$SOLR_PORT -sTCP:LISTEN`
        if [ -z "$running" ]; then
	  slept=$((loops * 2))
          if [ $slept -lt $SOLR_STOP_WAIT ]; then
            sleep 2
            loops=$[$loops+1]
          else
            echo -e "Still not seeing Solr listening on $SOLR_PORT after $SOLR_STOP_WAIT seconds!"
            tail -30 "$SOLR_LOGS_DIR/solr.log"
            exit # subshell!
          fi
        else
          SOLR_PID=`ps auxww | grep start\.jar | grep -w "\-Djetty\.port=$SOLR_PORT" | grep -v grep | awk '{print $2}' | sort -r`
          echo -e "\nStarted Solr server on port $SOLR_PORT (pid=$SOLR_PID). Happy searching!\n"
          exit # subshell!
        fi
      done) &
      spinner $!
    else
      echo -e "NOTE: Please install lsof as this script needs it to determine if Solr is listening on port $SOLR_PORT."
      sleep 10
      SOLR_PID=`ps auxww | grep start\.jar | grep -w "\-Djetty\.port=$SOLR_PORT" | grep -v grep | awk '{print $2}' | sort -r`
      echo -e "\nStarted Solr server on port $SOLR_PORT (pid=$SOLR_PID). Happy searching!\n"
      return;
    fi
  fi
}

launch_solr "$FG" "$ADDITIONAL_CMD_OPTS"

exit $?
