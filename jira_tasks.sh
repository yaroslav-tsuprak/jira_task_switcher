#!/usr/bin/env bash
# Скрипт переключает задачи в Jira из статуса REVIEW в TESTING. Если задача была не в REVIEW то она не будет переключена
# Работает только с master branch
# Перед запуском необходимо зайти в /srv и склонировать репозитарий редактора git clone --single-branch --branch master https://bitbucket.aigen.ru/scm/aigen/ed.git
# Пример запуска: bash jira_tasks.sh [first_hash] [second_hash]
# first_hash - первый короткий хэш коммита с которого будет совершена выборка
# second_hash - последний короткий хэш коммита по который будет совершена выборка

set -e

FIRST_HASH="$1"
SECOND_HASH="$2"
JIRA_FILE_CREDENTIALS="jira_settings"
DEBUG=false

function info {
  logger -t "jirascript" -p info "$1"
}

function check_requirements {
  # Если нету файла jira_settings то создаем его с переменными JIRA_USER и JIRA_PASSWORD
  if [ ! -f "${JIRA_FILE_CREDENTIALS}" ]
  then
    info "Missing file: jira_settings"
    info "Created a new file: jira_settings"
    echo -e "JIRA_USER=\nJIRA_PASSWORD=" >> $JIRA_FILE_CREDENTIALS
    exit 1
  fi

  # Settings in file "jira_settings" should define following variables:
  # JIRA_USER
  # JIRA_PASSWORD
  source ${JIRA_FILE_CREDENTIALS}

  if [ -z ${JIRA_USER} ] || [ -z ${JIRA_PASSWORD} ]; then
    info "Missing required settings in jira_settings file"
    exit 1
  fi

  if [ -z ${FIRST_HASH} ] || [ -z ${SECOND_HASH} ]; then
    info "Missing required settings!"
    info "An example: jira_tasks.sh [first_hash] [second_hash]"
    exit 1
  fi

  if [ ! -d "/srv/ed" ]; then
    info "Directory /srv/ed DOES NOT exists."
    info "Please, clone master branch to /srv before"
    exit 1
  fi
}

function switch_task_status() {
  result=`curl -sS -u ${JIRA_USER}:${JIRA_PASSWORD} -XPOST -H 'Content-Type: application/json' -d '{"transition":{"id":'${1}'}}' https://jira.aigen.ru/rest/api/latest/issue/${2}/transitions?.fields`
  if [[ $DEBUG ]]; then
    info "DEBUG: switch_task_status: ID ${1} - TASK ${2}"
    [[ ! -z ${result} ]] && info "DEBUG: switch_task_status: Web request result: ${result}"
  fi
  info "Jira task ${2} have been switched to Testing"
}

function check_task() {
  task=${1}
  [[ $DEBUG ]] && info "DEBUG: check_task: Checking Jira task ${task}"
  # Get task info
  result=$(curl -sS -u ${JIRA_USER}:${JIRA_PASSWORD} -XGET -H 'Content-Type: application/json' https://jira.aigen.ru/rest/api/2/issue/$task/transitions)
  if [[ "$result" =~ .*"error".*  ]]; then
    info "Jira task ${task} is not found"
  else
    i=0
    echo $result | jq '.transitions[] | .id' | while read id; do
      [[ $DEBUG ]] && info "DEBUG: check_task: Task status ID: ${id}"
      name=$(echo $result | jq '.transitions['${i}'] | .name')
      ((i=i+1))
      [[ $DEBUG ]] && info "DEBUG: check_task: Task status NAME: ${name}"
      # If task status name contains "esting" then we can switch it to Testing
      [[ "$name" =~ .*"esting".*  ]] && switch_task_status $id $task
    done
  fi
}

function main {
  check_requirements
  pushd /srv/ed
  # Update local repository
  git pull
  git log --oneline --no-merges ${FIRST_HASH}~1..${SECOND_HASH} | grep -o '[A-Z]\+\-[0-9]\+' | sort | uniq | while read line; do
    check_task $line
  done
  popd
  exit 0
}

main