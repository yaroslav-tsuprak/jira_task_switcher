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

function info {
  logger -t "jirascript" -p info "$1"
}

# Если нету файла jira_settings то создаем его с переменными JIRA_USER и JIRA_PASSWORD
if [ ! -f "${JIRA_FILE_CREDENTIALS}" ]
then
    info "Missing file: jira_settings"
    info "Created a new file: jira_settings"
    echo -e "JIRA_USER=\nJIRA_PASSWORD=" >> $JIRA_FILE_CREDENTIALS
fi

# Settings in file "jira_settings" should define following variables:
# JIRA_USER
# JIRA_PASSWORD
source ${JIRA_FILE_CREDENTIALS}

if [ -z ${JIRA_USER} ] || [ -z ${JIRA_PASSWORD} ]
then
    info "Missing required settings in jira_settings file"
    exit 0
fi

if [ -z ${FIRST_HASH} ] || [ -z ${SECOND_HASH} ]
then
  info "Missing required settings!"
  info "An example: jira_tasks.sh [first_hash] [second_hash]"
  exit 0
fi

if [ ! -d "/srv/ed" ]
then
    info "Directory /srv/ed DOES NOT exists."
    info "Please, clone master branch to /srv before"
    exit 0
fi

# сигнатура названий проектов и ID статуса TESTING в Jira
SIGNATURES=(DE USD CEL OU)
declare -A JIRA_TASK_STATUS_ID
JIRA_TASK_STATUS_ID+=( ["${SIGNATURES[0]}"]=41 ["${SIGNATURES[1]}"]=41 ["${SIGNATURES[2]}"]=81 ["${SIGNATURES[3]}"]=00 )
# Массив для сохранения обработанных номеров задач Jira
declare -A ID_ARRAY

pushd /srv/ed
# Update local repository
git pull

ifs_backup=$IFS
IFS=$(echo -en "\n")
# Выбираем коммиты из ветки мастер по коротким хэшам
readarray -t lines < <(git log --oneline --no-merges ${FIRST_HASH}~1..${SECOND_HASH})
popd

for text in ${lines[@]}
do
    HASH=`echo "${text}" | awk '{print $1}'`
    ID=`echo "${text}" | awk '{print $2}'`
    SIG=`echo $ID | cut -f1 -d"-"`
    if [[ ${SIGNATURES[@]} =~ $SIG ]]; then
        if echo "${ID_ARRAY[@]}" | grep -x -q "$ID"; then
            # Найден дубликат номера задачи Jira, второй раз не сохраняем
            true;
        else
            info "Found commit: ${HASH} and Jira Tiket ID: ${ID}"
            # Найден новый номер задачи Jira, сохраняем его
            id_array+=(${ID})
            # меняем статус задачи в Jira на "81" (TESTED)
            result=`curl -u ${JIRA_USER}:${JIRA_PASSWORD} -X POST --data '{"transition":{"id":"${JIRA_TASK_STATUS_ID[$SIG]}"}}' -H "Content-Type: application/json" https://jira.aigen.ru/rest/api/latest/issue/${ID}/transitions?.fields`
            if [ ! -n "$result" ]
            then
              info "Jira task ID: ${ID} status changed to [TESTING]"
            else
              info "Jira task ID: ${ID} status change [Error!]"
            fi
        fi
    fi
done
IFS=$ifs_backup