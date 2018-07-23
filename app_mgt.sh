#!/bin/bash

SCRIPT_NAME=$(basename "$0")
BASEDIR=$(dirname $0)

: "${TMPDIR:=${TMP:-$(CDPATH=/:/var; cd -P tmp)}}"

# Constants
EMPTY_DEPLOY_KEY="<empty>"
SERVICE_DATA_FOLDER="$TMPDIR/app_mgt"
WATCH_OUTPUT_DIR="$SERVICE_DATA_FOLDER/app_output"
LOG_FILE_START_LINE="Started "
LOG_FILE_FAILED_LINE="APPLICATION FAILED TO START"
LOG_FILE_STARTED_ON_PORT="started on port"

DEPLOY_KEY="deployment.key"
DEPLOY_PARAMS_PREFIX="deployment.params"
DEPLOY_PARAMS_WATCH=$DEPLOY_PARAMS_PREFIX".watch"
DEPLOY_PARAMS_ACTUATOR_PATH=$DEPLOY_PARAMS_PREFIX".actuator_path"
DEPLOY_PARAMS_TIMEOUT=$DEPLOY_PARAMS_PREFIX".timeout"

DEFAULT_ACTUATOR_PATH="manage/"
DEFAULT_TIMEOUT=90
DEFAULT_LOG_FILE="/dev/null"

# Utils variables
unset cmdLine
unset resCmdLine
unset logFile

# Global variables
unset listDetails
unset logsDetails
unset appName
unset action
unset pid
unset pidArr
unset pidArrIndex
unset port
unset portArr
unset portArrIndex
unset start_command
unset jarPath
unset jarName
unset applicationPortFile
unset applicationPidFile
unset actuator_path
unset timeout
unset watch_log
unset kill_direct
unset nb_inst
unset appsArr
unset appsArrIndex
unset deployKeysArr
unset deployKeysArrIndex

# Global variable options
unset deployment_key
unset eureka_prop
unset java_home
unset profile_option
unset port_option
unset actuator_path_option
unset timeout_option
unset nb_inst_option
unset params_option_array
unset file_option
params_option_index=0
ibm_option=false
watch_option=false
kill_option=false
details_option=false
debug_option=false
trace_option=false

#########################################################################
# Utils
#########################################################################

function usage {
  print
  print "Usage: "
  print

  increment_print_tabs 
  print "$SCRIPT_NAME [logging_option] action [list_option|logs_method] [application name] [options]"
  print
  decrement_print_tabs

  print "Logging:"
  increment_print_tabs
    print "-d | --debug"
    increment_print_tabs
      print "All actions parameter. Debug option."
    decrement_print_tabs
    print "-tr | --trace"
    increment_print_tabs
      print "All actions parameter. Trace option."
    decrement_print_tabs
  decrement_print_tabs
  print

  print "Global actions:"
  increment_print_tabs
    print "list\tList available applications. It needs a following option: apps (or a), deploy_keys (or dks), ports or pids. The last 3 needs also the application name."
  print
  decrement_print_tabs
  print "Application actions (need the '-a|--app' parameter):"
  increment_print_tabs
    print "start        Start the application. You can add parameters (see after)"
    print "stop         Stop the application. You can add parameters (see after)"
    print "restart      Restart the application. You can add parameters -p or --nb (see after)"
    print "status       Give a status of all current running instances"
    print "nb           Give the number of instances supposed to run"
    print "logs         Display the logs for the given port. Port is mandatory. As well as the file option. Note: You need to give which reader (logs_reader) to use. This will give something like: '$SCRIPT_NAME logs more [app] -f {filepath} -p {port}'"
  decrement_print_tabs
  print

  print "Available options:"
  increment_print_tabs
    print "-dk | --deploy_key"
    print "\tAll actions parameter. Deployment key used to recognize the launched instances. If none given, a default <empty> one will be assigned."
    print
    print "-dt | --details"
    print "\tList parameter. Give more details on the list of the displayed list."
    print "-p | --port"
    print "\tStart/Stop/isRunning parameter. Server port on which the application should be launched/stopped. Will set the parameter 'server.port' on start or check running for isRunning command."
    print "-to | --timeout"
    print "\tStart/Stop parameter. Timeout in seconds. 60 seconds by default."
    print "-pf | --profile"
    print "\tStart parameter. Profile(s) to use. Will set the parameter 'spring.profiles.active'."
    print "-es | --eureka_server"
    print "\tStart parameter. Discovery server url to target."
    print "-jh | --java_home"
    print "\tStart parameter. Bin directory containing java command."
    print "-ibm | --ibm"
    print "\tStart parameter. Precise this is an IBM system."
    print "-w | --watch"
    print "\tStart parameter. Watch the log for application start or stop instead of using actuator endpoint."
    print "-pa | --param"
    print "\tStart parameter. Many values. Extra parameter that you can give directly to the start of the application."
    print "-ap | --actuator_path"
    print "\tStop/Status parameter. Actuator path. This parameter gives on which prefix path are actuator services (status & smooth stop). 'manage/' by default."
    print "-f | --file"
    print "\tLogs parameter. Filepath to the log file. You can use env variables as well as {pid} and {port} placeholders."
    print "-k | --kill"
    print "\tStop parameter. Kill -9 directly the application. No smooth stop ..."
    print "-n | --nb_inst"
    print "\tStart/Stop/Restart parameter. Give the number of instances to start/stop/restart or that should be running (check) ..."
  decrement_print_tabs
  print
}

print_tab=0

function increment_print_tabs {
  print_tab=$((print_tab+1))
}

function decrement_print_tabs {
  if [[ $print_tab -ge 1 ]]; then
    print_tab=$((print_tab-1))
  fi
}

# print msg [no_return] [no_tabs]
function print {
  local msg="$1"

  if [[ -z $2 ]] || [[ "$2" != "false" ]]; then
    msg="$msg\n"
  fi

  if [[ -z $3 ]] || [[ "$3" != "false" ]]; then
    for i in $(seq 1 $print_tab); 
    do 
      msg="\t$msg"; 
    done
  fi

  printf "$msg"
}

function errorPrint {
  local msg=$1
  if [[ ! -z $msg ]]; then
    msg="ERROR: $msg"
  fi
  print "$msg" $2 $3
}

function warningPrint {
  local msg=$1
  if [[ ! -z $msg ]]; then
    msg="WARN: $msg"
  fi
  print "$msg" $2 $3

}

function debugPrint {
  local msg=$1
  if [ "$debug_option" = true ]; then
    if [[ ! -z $msg ]]; then
      msg="DEBUG: $msg"
    fi
    print "$msg" $2 $3
  fi
}

function tracePrint {
  local msg=$1
  if [ "$trace_option" = true ]; then
    if [[ ! -z $msg ]]; then
      msg="TRACE: $msg"
    fi
    print "$msg" $2 $3
  fi
}

function exeShellCmdLine {
  unset resCmdLine

  local resFilename="tmp_$appName_.$RANDOM"

  cmdLine="$cmdLine > $resFilename"

  tracePrint "exeShellCmdLine with command = $cmdLine"

  eval $cmdLine
  resCmdLine=`cat "$resFilename"`

  tracePrint "exeShellCmdLine result = $resCmdLine"

  rm -rf "$resFilename"

  unset cmdLine
}

function exeCurl {
  curlUrl=$1
  curlMethod=$2
  if [[ -z "$curlMethod" ]]; then
    curlMethod="GET"
  fi

  tracePrint "exeCurl with url $curlUrl and method $curlMethod"

  curlOutput=$(curl -si -d "" --request "$curlMethod" http://$curlUrl)
  curlHeader=""
  curlBody=""
  curlStatus=""

  local head=true
  while read -r line; do 
    if $head; then 
      if [[ $line = $'\r' ]]; then
        head=false
      else
        curlHeader="$curlHeader"$'\n'"$line"
      fi
    else
      curlBody="$curlBody"$'\n'"$line"
    fi
  done < <(echo "$curlOutput")

  curlBody=$(echo "$curlBody" | tr -d [:space:])
  curlStatus=$(echo "$curlHeader" | grep HTTP | awk '{print $2}')

  tracePrint "Got status $curlStatus and body $curlBody"
}

function containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function checkAppName {
  # Get app name as second arg
  if [ "$appName" == "" ]; then
    errorPrint "Need an application name to execute ..."
    errorPrint
    usage
    exit 1
  fi

  if [ ! -d "$appName" ]; then
    errorPrint "$appName does not exist ...\n\n"
    usage
    exit 1
  fi
}

function getApps {
  unset appsArr
  appsArrIndex=0

  cmdLine="for i in \$(ls -d */); do echo \${i%%/}; done"
  exeShellCmdLine
  
  while read -r value
  do
    tracePrint "Got folder $value"
    jar=`find $value -name "$value*.jar"`
    if [[ ! -z $jar ]]; then
      tracePrint "Got jar $jar"
      appsArr[appsArrIndex]=$value
      appsArrIndex=$((appsArrIndex+1))
    fi
  done < <(printf '%s\n' "$resCmdLine")
}

function getDeploymentKeys {
  unset deployKeysArr
  deployKeysArrIndex=0

  # Get process without deployment key
  cmdLine="ps -ef | grep $appName | grep -v grep | grep -v $SCRIPT_NAME | grep -v \"deployment\.key\" | wc -l | tr -d '[:space:]'"
  exeShellCmdLine
  if [[ "$resCmdLine" != "0" ]]; then
    tracePrint "Add <empty> deployment key\n"
    deployKeysArr[deployKeysArrIndex]=$EMPTY_DEPLOY_KEY
    deployKeysArrIndex=$((deployKeysArrIndex+1))
  fi

  # Get deployment keys
  cmdLine="ps -ef | grep $appName | grep -v grep | grep -v $SCRIPT_NAME | grep \"deployment\.key\"  | awk '{ s = \"\"; for (i = 9; i <= NF; i++) s = s \$i \" \"; print s }' | tr ' ' '\\n' | grep $DEPLOY_KEY | awk -F'[=]' '{print \$2}'"
  exeShellCmdLine

  while read -r value
  do
    tracePrint "Got value $value"
    if ! containsElement "$value" "${deployKeysArr[@]}" && [[ ! -z $value ]]; then
      tracePrint "Add deployment key $value"
      deployKeysArr[deployKeysArrIndex]=$value
      deployKeysArrIndex=$((deployKeysArrIndex+1))
    fi
  done < <(printf '%s\n' "$resCmdLine")
}


#########################################################################
# Functions
#########################################################################

function setupEnv {
  debugPrint "Setup environment"

  increment_print_tabs

  if test -n "$java_home"; then
    java_home="$java_home/java"
  elif test -n "$JAVA_HOME"; then
    java_home="$JAVA_HOME/bin/java"
  else
    java_home="java"
  fi
  debugPrint "java_home=$java_home"

  # Create data folders
  mkdir -p "$WATCH_OUTPUT_DIR"
  
  # Calculate jar name
  if [[ ! -z $appName ]];then
    jarPath=`find $appName -name "$appName*.jar"`
    jarName=`basename $jarPath`
    applicationPortFile="$appName/application.port"
    applicationPidFile="$appName/application.pid"
    
    debugPrint "Jar found = $jarName in $jarPath"
    debugPrint "applicationPortFile = $applicationPortFile"
    debugPrint "applicationPidFile = $applicationPidFile"
  fi

  if [[ -z $deployment_key ]]; then
    debugPrint "Set empty deployment_key"
    deployment_key=$EMPTY_DEPLOY_KEY
  fi

  if [ -z actuator_path_option ]; then
    actuator_path="$actuator_path_option"
  else
    actuator_path="$DEFAULT_ACTUATOR_PATH"
  fi
  debugPrint "actuator_path=$actuator_path"

  if [ -z timeout_option ]; then
    timeout=$timeout_option
  else
    timeout=$DEFAULT_TIMEOUT
  fi
  debugPrint "timeout=$timeout"

  if [[ "$kill_option" == "true" ]]; then
    kill_direct=true
  else
    kill_direct=false
  fi
  debugPrint "kill=$kill_direct"

  if [[ "$watch_option" == "true" ]]; then
    watch_log=true
  else
    watch_log=false
  fi
  debugPrint "watch log=$watch_log"

  if [[ ! -z $nb_inst_option ]]; then
    debugPrint "Set nb inst $nb_inst_option"
    nb_inst=$nb_inst_option
  fi

  decrement_print_tabs
}

# Parse port option
function parsePortOption {
  tracePrint "parsePortOption"

  getRunningPorts

  local runningPorts=( "${portArr[@]}" )
  local setRunningPortsDefault=$1
  local checkWithRunningPorts=$2
  if [[ -z $checkWithRunningPorts ]]; then
    checkWithRunningPorts=true
  fi
  unset portArr
  portArrIndex=0

  tracePrint "Set running ports default = $setRunningPortsDefault"
  tracePrint "Check with running ports = $checkWithRunningPorts"

  if [[ ! -z $port_option ]]; then
    cmdLine="echo \"$port_option\" | tr \",\" \"\\\\n\""
    exeShellCmdLine

    while read -r value
    do
      if [[ ! -z $value ]]; then
        if [ "$checkWithRunningPorts" = "false" ] || containsElement "$value" "${runningPorts[@]}"
        then
          tracePrint "Add port $value"
          portArr[portArrIndex]=$value
          portArrIndex=$((portArrIndex+1))
        else
          warningPrint "Port $value is not available for this deployment_key... Ignored ..."
        fi
      fi
    done < <(printf '%s\n' "$resCmdLine")
  elif [ "$setRunningPortsDefault" = "true" ]; then
    debugPrint "Set Running Ports Default"
    portArr=( "${runningPorts[@]}" )
  fi

  local ports=""
  for p in "${portArr[@]}"
  do
    ports=$ports" $p"
    tracePrint "Got port $p"
  done
  debugPrint "Got ports $ports"
}

function getLaunchedAppPort { 
  if [ -f $applicationPortFile ]; then
    port=`cat $applicationPortFile`
    rm -rf $applicationPortFile
  fi
}

function getLaunchedAppPid {
  if [ -f $applicationPidFile ]; then
    pid=`cat $applicationPidFile`
    rm -rf $applicationPidFile
  fi
}

function getRunningPids {
  unset pidArr
  pidArrIndex=0

  cmdLine="ps -ef | grep $appName | grep -v grep | grep -v $SCRIPT_NAME"
  if [[ "$deployment_key" != "$EMPTY_DEPLOY_KEY" ]]; then
    cmdLine="$cmdLine | grep \"$DEPLOY_KEY=$deployment_key \""
  else
    cmdLine="$cmdLine | grep -v \"$DEPLOY_KEY\""
  fi
  cmdLine="$cmdLine | awk '{print \$2}'"

  exeShellCmdLine

  while read -r value
  do
    pidArr[pidArrIndex]=$value
    pidArrIndex=$((pidArrIndex+1))
  done < <(printf '%s\n' "$resCmdLine")
}

function getRunningPorts {
  unset portArr
  portArrIndex=0

  getRunningPids

  local oldPort=$port

  if [[ ! -z $pidArr ]]; then
    for pid in "${pidArr[@]}"
    do
      getPortFromPid
      if [[ ! -z $port ]]; then
        portArr[portArrIndex]=$port
        portArrIndex=$((portArrIndex+1))
      fi
    done
  fi

  port=$oldPort
}

function getPortFromPid {
  tracePrint "getPortFromPid $pid"

  unset port
  cmdLine="lsof -i 2>/dev/null | grep $pid | grep LISTEN | grep -v lsof | awk '{print \$9}' | sed -e 's/*://g'"
  exeShellCmdLine
  port=$resCmdLine
}

function getPidFromPort {
  tracePrint "getPidFromPort $port"

  unset pid
  cmdLine="lsof -i 2>/dev/null | grep $port | grep LISTEN | grep -v lsof | awk '{print \$2}'"
  exeShellCmdLine
  pid=$resCmdLine
}

function getStartCommandFromOptions {
  tracePrint "getStartCommandFromOptions"

  unset start_command
  if test -n "$1"; then
    prop="$1"
  fi
  
  unset instrumentation
  if [ "$ibm_option" = true ]; then
    instrumentation="-XX:-RuntimeInstrumentation"
  fi
  
  params=""
  if [ ! -z "$params_option_array" ]; then
    for param in "${params_option_array[@]}"
    do
      params=$params" "$param
    done
  fi

  # Add Deployment params (specific start options, for later possible restart)
  if [[ ! -z $deployment_key ]] && [[ "$deployment_key" != "$EMPTY_DEPLOY_KEY" ]]; then
    params=$params" $DEPLOY_KEY=$deployment_key"
  fi
  if [ "$watch_log" = true ]; then
    params=$params" $DEPLOY_PARAMS_WATCH"
  fi
  if [[ ! -z $timeout_option ]]; then
    params=$params" $DEPLOY_PARAMS_TIMEOUT=$timeout_option"
  fi
  if [[ ! -z $actuator_path_option ]]; then
    params=$params" $DEPLOY_PARAMS_ACTUATOR_PATH=$actuator_path_option"
  fi
  
  start_command="cd $appName && $java_home -jar $instrumentation $jarName $prop $eureka_prop $params"

  tracePrint "getStartCommandFromOptions result => $start_command"
}


function parseStartCommandFromPid {
  unset start_command
  cmdLine="ps -ef | grep $pid | grep -v grep | awk '{ s = \"\"; for (i = 9; i <= NF; i++) s = s \$i \" \"; print s }'"
  exeShellCmdLine
  start_command="cd $appName && $java_home $resCmdLine"

  tracePrint "$start_command"

  if [[ $resCmdLine =~ "$DEPLOY_PARAMS_WATCH" ]]; then
    watch_log=true
  else
    watch_log=false
  fi
  debugPrint "Watch log = $watch_log"

  if [[ -z $timeout_option ]] && [[ $resCmdLine =~ "$DEPLOY_PARAMS_TIMEOUT" ]]; then
    timeout=$(echo "$resCmdLine" | awk "BEGIN {RS=\" \"}; /$DEPLOY_PARAMS_TIMEOUT/" | tr -d '[:space:]' | awk -F '=' '{print $2}')
  elif [[ ! -z $timeout_option ]]; then
    timeout=$timeout_option
  else
    timeout=$DEFAULT_TIMEOUT
  fi
  debugPrint "Timeout = $timeout"

  if [[ $resCmdLine =~ "$DEPLOY_PARAMS_ACTUATOR_PATH" ]]; then
    actuator_path=$(echo "$resCmdLine" | awk "BEGIN {RS=\" \"}; /$DEPLOY_PARAMS_ACTUATOR_PATH/" | tr -d '[:space:]' | awk -F '=' '{print $2}')
  else
    actuator_path=$DEFAULT_ACTUATOR_PATH
  fi
  debugPrint "Actuator Path = $actuator_path"
}

#########################################################################
# Utils methods
#########################################################################

function check_if_process_is_running {
  tracePrint "check_if_process_is_running with pid $pid"
  ps -p $pid > /dev/null
  return $?
}

function stopPid {
  if [ $pid ]; then
    debugPrint "Kill process with pid $pid"
    
    local status=1
    kill $pid > /dev/null 2>&1

    debugPrint "Smooth Killing... Waiting for process to stop..." false
    i=1; while [ $i -le $timeout ] && [[ "$status" != "0" ]]; do
      if check_if_process_is_running
      then
        debugPrint "." false false
        sleep 1
      else
        status=0
      fi
      i=$(($i + 1))
    done
    debugPrint
	  
    if [[ "$status" != "0" ]]; then
      print "Cannot kill smoothly the process with pid $pid. Kill drastically."
      kill -9 $pid > /dev/null 2>&1
      return 1
    fi
    return 0
  else
    warningPrint "No pid found to be stopped. Unknown instance..."
    return 0
  fi
}

function setLogFile {
  logFile="$DEFAULT_LOG_FILE"
  if [ "$watch_log" = true -o "$debug_option" = true ]; then
    logFile="${WATCH_OUTPUT_DIR}/output.$RANDOM"
  fi
}

function watchBootFiles {
  print "Wait for $applicationPidFile and $applicationPortFile files for start"
  print "Starting..." false
  
  status=1
  i=1; while [ $i -le $timeout ]; do
    if [ -f $applicationPortFile ]; then
      getLaunchedAppPid
      getLaunchedAppPort
      status=0
      break
    else
      print "." false false
      sleep 1
    fi
    i=$(($i + 1))
  done

  print

  return $status
}

function watchLogFile {	
  print "Watch log output file with timeout $timeout"
  print "Starting..." false
	
  # Let time for the log file to be created
  sleep 2

  status=1
  j=1; while [ $j -le $timeout ]; do
    print "." false false

    line=`less "$logFile" | grep "$LOG_FILE_STARTED_ON_PORT"`
    if [[ "$line" != "" ]]; then
      temp_port=$(echo "$line" | cut -d "$LOG_FILE_STARTED_ON_PORT" -f 4 | tr -dc '0-9')
      port=$(($temp_port))
      temp_pid=$(echo "$line" | cut -d "INFO" -f 2 | cut -d "$LOG_FILE_STARTED_ON_PORT" -f 1 |  tr -dc '0-9')
      pid=$(($temp_pid))
			
      debugPrint "Got port $port and pid $pid"
    fi

    line=`less "$logFile" | grep "$LOG_FILE_START_LINE"`
    if [[ "$line" != "" ]]; then
      status=0
      break
    fi
    line=`less "$logFile" | grep "$LOG_FILE_FAILED_LINE"`
    if [[ "$line" != "" ]]; then
      break
    fi
    sleep 1
    j=$(($j + 1))
  done
  print

  return $status
}

function startApp {
  # check start command has been set
  if [[ -z $start_command ]]; then
    errorPrint "Please call one 'getStartCommand*' methods before ..."
    exit 1
  fi

  if [[ ! -z $port ]] && [[ "$port" != "0" ]]; then
    getPidFromPort

    if [[ ! -z $pid ]] && check_if_process_is_running
    then
      print "Application is already running on port $port ... Use restart if needed ..."
      return 0
    fi
  fi

  setLogFile
  
  print "Start application $appName with command: $start_command"
  print "Log output file: $logFile"

  nohup sh -c "$start_command" > $logFile 2>&1 &
  
  increment_print_tabs

  local status=0
  if [ "$watch_log" = true ]; then
    watchLogFile
  else
    watchBootFiles
  fi
  status=$?
 
  if [[ "$status" != "0" ]]; then
    print "Problem starting application $appName on port $port"
    stopPid
    status=1
  else
    print "Application started on port $port, with pid $pid"
  fi

  decrement_print_tabs

  unset port
  return $status
}

function stopApp {
  print "Stop application on port: $port" false

  increment_print_tabs

  local status=0

  unset pids
  getPidFromPort
  parseStartCommandFromPid

  debugPrint
  local status=1
  if [ "$kill_direct" = false ]; then
    url="localhost:$port/"$actuator_path"shutdown"
  
    debugPrint "Stopping smoothly application via actuator url $url" false

    exeCurl $url "POST"
	  
    status=$?
    if [ $status != 0 ] ; then
      debugPrint 
      debugPrint "FAILED !!!!! Server on port $port not responding"
      status=1
    elif [ "$curlStatus" != "200" ]; then
      debugPrint 
      debugPrint "FAILED !!!!! Problem while targeting url $url. Http error code=$curlStatus. Body = $curlBody"
      debugPrint "Response is: "
      status=1
    else
      status=1
      i=1; while [ $i -le $timeout ] && [[ "$status" != "0" ]]; do
        if check_if_process_is_running
        then
          print "." false false
          sleep 1
        else
          status=0
        fi
        i=$(($i + 1))
      done
    fi
    print
  
    if [[ "$status" != "0" ]]; then
      warningPrint "Problem stopping smoothly application $appName on port $port... Try to kill it ..."
    fi
  fi
  
  if [[ "$status" != "0" ]]; then
    if stopPid; then
      print "Process $pid stopped"
      status=0
    else
      print "Problems occured trying to stop application with pid $pid"
      status=1
    fi
  else
    print "Application stopped correctly"
  fi

  decrement_print_tabs

  return $status
}

function statusApp {
  tracePrint "Status of application on port $port : "
  
  increment_print_tabs

  url="localhost:$port/"$actuator_path"health"
  
  debugPrint "Check health of application via actuator url $url"
  
  exeCurl $url
	
  local status=$?
  if [ $status != 0 ] ; then
    errorPrint "Instance not available"
    status=1
  elif [ "$curlStatus" == "404" ]; then
    warningPrint "UP but Health Url does not exist: $curlStatus"
  elif [ "$curlStatus" != "200" ]; then
    errorPrint "Problem while targeting url $url. Http error code=$curlStatus"
    status=1
  fi

  decrement_print_tabs

  return $status
}

#########################################################################
## List Actions

function list {
  if [[ -z $listDetails ]]; then
    errorPrint "No details given. Please provide 'apps' (or 'a'), 'deploy_keys' (or 'dks'), 'ports' or 'pids'."
  elif [[ "$listDetails" == "apps" ]] || [[ "$listDetails" == "a" ]]; then
    listApps
  else
    checkAppName

    if [[ "$listDetails" == "deploy_keys" ]] || [[ "$listDetails" == "dks" ]]; then
      listDeploymentKeys
    elif [[ "$listDetails" == "ports" ]]; then
      listPorts
    elif [[ "$listDetails" == "pids" ]]; then
      listPids
    else
      errorPrint "Unknown details $listDetails. Please provide 'apps' (or 'a'), 'deploy_keys' (or 'dks'), 'ports' or 'pids'."
    fi
  fi
}

function listApps {
  tracePrint "List applications"
  getApps
  if [[ "$details_option" = true ]]; then
    print "APPS/DEPLOYMENT_KEY/TOTAL_INSTANCES/PORTS"
  else
    print "APPS"
  fi

  if [[ ! -z $appsArr ]]; then
    for app in "${appsArr[@]}"
    do
      appName=$app

      if [[ "$details_option" = true ]]; then
        getDeploymentKeys
        if [[ ! -z $deployKeysArr ]]; then
          for dk in "${deployKeysArr[@]}"
          do
            deployment_key=$dk
            getRunningPorts
            local ports=""
            if [[ ! -z $portArr ]]; then
              for p in "${portArr[@]}"
              do
                if [[ -z $ports ]]; then
                  ports=$p
                else
                  ports="$ports,$p"
                fi
              done
            fi
            print "$app/$dk/${#portArr[@]}/$ports"
          done
        else
          print "$app///"
        fi
      else
        print "$app"
      fi
    done
  else
    print "No application found ..."
  fi
}

function listDeploymentKeys {
  tracePrint "List deployment keys"
  getDeploymentKeys

  if [[ "$details_option" = true ]]; then
    print "DEPLOYMENT_KEY/NB_INSTANCES/PORTS"
  else
    print "DEPLOYMENT_KEY"
  fi

  if [[ ! -z $deployKeysArr ]]; then
    for dk in "${deployKeysArr[@]}"
    do
      deployment_key=$dk
       if [[ "$details_option" = true ]]; then
        getRunningPorts
        local ports=""
        if [[ ! -z $portArr ]]; then
          for p in "${portArr[@]}"
          do
            if [[ -z $ports ]]; then
              ports=$p
            else
              ports="$ports,$p"
            fi
          done
        fi
        print "$dk/${#portArr[@]}/$ports"
      else
        print "$dk"
      fi
    done
  else
    print "No deployment key found ..."
  fi
}

function listPorts {
  increment_print_tabs
  getRunningPorts
  decrement_print_tabs

  if [[ ! -z $portArr ]]; then
    for p in "${portArr[@]}"
    do
      print $p
    done
  else
    print "No port found..."
  fi
}

function listPids {
  parsePortOption true
  
  if [[ ! -z "$portArr" ]]; then
    for p in "${portArr[@]}"
    do
      port=$p
      getPidFromPort
      print "$port => $pid"
    done
  else
    print "No instance found ..."
  fi
}

#########################################################################
## Start / Stop / Restart

function status {
  parsePortOption true
  if [[ ! -z $portArr ]]; then
    for port in "${portArr[@]}"
    do
      statusApp $port
      if [ "$?" != 0 ] ; then
        exitStatus=1
      else
        print "$port => UP"
      fi
    done
  else
    print "No instance found..."
  fi
}

function stop {
  parsePortOption true

  nbToKill=${#portArr[@]}
  if [[ ! -z $nb_inst ]]; then
    nbToKill=$nb_inst
  fi

  if [[ ! -z $portArr ]]; then
    print "Stop $nbToKill instance(s)"
    nbStop=0
    increment_print_tabs
    for port in "${portArr[@]}"
    do
      stopApp
      if [ "$?" == 1 ] ; then
        exitStatus=1
      else
        nbStop=$((nbStop+1))
      fi
      if [ $nbStop -ge $nbToKill ]; then
        break;
      fi
    done
    decrement_print_tabs
  else
    print "No instance to stop..."
  fi
}

function start {
  parsePortOption false false

  profileParam=""
  portParam=""
  	
  if [[ ! -z $profile_option ]]; then
    profileParam="--spring.profiles.active=$profile_option"
  fi

  if [[ ! -z $portArr ]]; then
    increment_print_tabs
    for port in "${portArr[@]}"
    do
      portParam="--server.port=$port"
      getStartCommandFromOptions "$profileParam $portParam"
      startApp
      if [ "$?" == 1 ] ; then
        exitStatus=1
      fi
    done

    decrement_print_tabs
  else
    if [[ ! -z $nb_inst ]]; then
      print "Start $nb_inst instance(s). Port set automatically to 0 for each to avoid port conflict"
      portParam="--server.port=0"
 
      increment_print_tabs
      for i in `seq 1 $nb_inst`
      do
        getStartCommandFromOptions "$profileParam $portParam"
        startApp
        if [ "$?" == 1 ] ; then
          exitStatus=1
        fi
      done
      decrement_print_tabs
    else
      print "Start one instance"
      increment_print_tabs
      getStartCommandFromOptions "$profileParam $portParam"
      startApp
      if [ "$?" == 1 ] ; then
        exitStatus=1
      fi
      decrement_print_tabs
    fi
  fi
}

function restart {
  parsePortOption true

  nbToRestart=${#portArr[@]}
  if [[ ! -z $nb_inst ]]; then
    nbToRestart=$nb_inst
  fi

  if [[ ! -z $portArr ]]; then
    print "Restart $nbToRestart instance(s)"
    nb=0
    increment_print_tabs
    for port in "${portArr[@]}"
    do
      getPidFromPort
      parseStartCommandFromPid
      print "Restart instance on port $port"
      stopApp
      sleep 2
      startApp
      if [ "$?" == 1 ] ; then
        exitStatus=1
      else
        nb=$((nb+1))
      fi
      if [ $nb -ge $nbToRestart ]; then
        break;
      fi
    done
    decrement_print_tabs
  else
    print "No instance to restart..."
  fi
}

function showLogs {
  parsePortOption false true
  if [[ -z "$portArr" ]]; then
    errorPrint "You need to provide a port ..."  
  else
    for p in "${portArr[@]}"
    do
      port=$p
      getPidFromPort
      echo $file_option
      logFile=$(echo "$file_option" | sed -e "s/{pid}/${pid}/g")
      eval "$logsDetails $logFile"
      break
    done
  fi
}

#########################################################################
#########################################################################
#########################################################################
#########################################################################
#########################################################################
# Main
#########################################################################

# Get action to do on application
action=$1
if [ "$action" == "-d" ] || [ "$action" == "--debug" ]; then
  print "Set Debug mode"
  debug_option=true
  shift
  action=$1
elif [ "$action" == "-tr" ] || [ "$action" == "--trace" ]; then
  print "Set Trace mode"
  debug_option=true
  trace_option=true
  shift
  action=$1
fi

if [ "$action" == "" ] || [ "$action" == "help" ]; then
  usage
  exit 1
fi

shift

# Parse list details if exists
if [[ "$action" == "list" ]]; then
  if [[ $1 != -* ]]; then
    listDetails=$1
    tracePrint "Got list details $listDetails"
    shift
  fi
elif [[ "$action" == "logs" ]]; then
  logsDetails=$1
  tracePrint "Got list details $logsDetails"
  shift
fi

if [[ $1 != -* ]]; then
  appName=$1

  appName=${appName%/}
  tracePrint "Got app $appName"
  shift
fi


debugPrint "--------------------------------------------------------------------" 
debugPrint "Read options from command line" 
debugPrint "--------------------------------------------------------------------" 

increment_print_tabs
while [ "$1" != "" ]; do
  case $1 in
    -dk | --deploy_key )    
      shift
      debugPrint "=> Set Deployment Key $1"
      deployment_key=$1
      ;;

    -pf | --profile )       
      shift
      debugPrint "=> Set Profile $1"
      profile_option=$1
      ;;

    -ibm | --ibm )
      debugPrint "=> IBM system"
      ibm_option=true
      ;;                               	

    -p | --port )
      shift
      debugPrint "=> Set Port $1"
      port_option=$1
      ;;

    -to | --timeout )
      shift
      debugPrint "=> Set timeout $1"
      timeout_option=$1
      ;;
    
    -es | --eureka_server ) 
      shift
      debugPrint "=> Set eureka server $1"
      eureka_prop="--eureka.client.serviceUrl.defaultZone=$1"
      ;;

    -jh | --java_home )
      shift
      debugPrint "=> Set java home $1"
      java_home=$1
      ;;

    -ap | --actuator_path )
      shift
      debugPrint "=> Set Actuator path $1"
      actuator_path_option=$1
      ;;

    -n | --nb_inst )
      shift
      debugPrint "=> Set number of instances $1"
      nb_inst_option=$1
      ;;

    -w | --watch )
      debugPrint "=> Watch logs"
      watch_option=true
      ;;

    -k | --kill )
      debugPrint "=> Kill -9"
      kill_option=true
      ;;

    -dt | --details )
      debugPrint "=> Give details"
      details_option=true
      ;;

    -pa | --param )
      shift
      debugPrint "=> Add Param $1"
      params_option_array[params_option_index]=$1
      params_option_index=$((params_option_index+1))
      ;;

    -f | --file )
      shift
      debugPrint "=> Add File $1"
      file_option=$1
      ;;

    -h | --help )
      usage
      exit
      ;;

    * )
      usage
      exit 1
  esac
  shift
done
decrement_print_tabs

debugPrint
debugPrint "--------------------------------------------------------------------" 
debugPrint "Setup Environment" 
debugPrint "--------------------------------------------------------------------" 

increment_print_tabs
  setupEnv
decrement_print_tabs

debugPrint
debugPrint "--------------------------------------------------------------------"
debugPrint "Process the command"
debugPrint "--------------------------------------------------------------------"

exitStatus=0

debugPrint
case "$action" in
  # Global actions
  list)
    list
  ;;

  # App actions
  status)
    checkAppName
    status
    ;;

  logs)
    checkAppName
    showLogs
    ;;
    
  stop)
    checkAppName
    stop
    ;;
    
  start)
    checkAppName
    start
    ;;
  
  restart)
    checkAppName
    restart
    ;;
    
  nb)  	
    checkAppName
    getRunningPids
    print "${#pidArr[@]}"
    ;;
  	
  *)
    usage
    exit 1
esac
exit $exitStatus