#!/bin/bash
{{/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

set -ex

function create_test_index () {
  index_result=$(curl -K- <<< "--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" \
  -XPUT "${ELASTICSEARCH_ENDPOINT}/test_index?pretty" -H 'Content-Type: application/json' -d'
  {
    "settings" : {
      "index" : {
        "number_of_shards" : 3,
        "number_of_replicas" : 2
      }
    }
  }
  ' | python -c "import sys, json; print(json.load(sys.stdin)['acknowledged'])")
  if [ "$index_result" == "True" ];
  then
    echo "PASS: Test index created!";
  else
    echo "FAIL: Test index not created!";
    exit 1;
  fi
}

{{ if not (empty .Values.conf.api_objects) }}

function test_api_object_creation () {
  NUM_ERRORS=0
  {{ range $object, $config := .Values.conf.api_objects }}
  error=$(curl -K- <<< "--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" \
            -XGET "${ELASTICSEARCH_ENDPOINT}/{{ $config.endpoint }}" | jq -r '.error')

  if [ $error == "null" ]; then
      echo "PASS: {{ $object }} is verified."
    else
      echo "FAIL: Error for {{ $object }}: $(echo $error | jq -r)"
      NUM_ERRORS=$(($NUM_ERRORS+1))
    fi
  {{ end }}

  if [ $NUM_ERRORS -gt 0 ]; then
    echo "FAIL: Some API Objects were not created!"
    exit 1
  else
    echo "PASS: API Objects are verified!"
  fi
}

{{ end }}

{{ if .Values.conf.elasticsearch.snapshots.enabled }}
function check_snapshot_repositories_verified () {
  repositories=$(curl -K- <<< "--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" \
                  "${ELASTICSEARCH_ENDPOINT}/_snapshot" | jq -r "keys | @sh" )

  repositories=$(echo $repositories | sed "s/'//g") # Strip single quotes from jq output

  for repository in $repositories; do
    error=$(curl -K- <<< "--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" \
            -XPOST "${ELASTICSEARCH_ENDPOINT}/_snapshot/${repository}/_verify" | jq -r '.error')

    if [ $error == "null" ]; then
      echo "PASS: $repository is verified."
    else
      echo "FAIL: Error for $repository: $(echo $error | jq -r)"
      exit 1;
    fi
  done
}
{{ end }}

function remove_test_index () {
  echo "Deleting index created for service testing"
  curl -K- <<< "--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" \
  -XDELETE "${ELASTICSEARCH_ENDPOINT}/test_index"
}

remove_test_index || true
create_test_index
remove_test_index
test_api_object_creation
{{ if .Values.conf.elasticsearch.snapshots.enabled }}
check_snapshot_repositories_verified
{{ end }}
