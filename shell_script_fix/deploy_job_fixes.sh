#!/bin/bash
###############################################################################
# TARGETED FIXES for Databricks Job Deployment Script
# ============================================================================
# Replace the corresponding blocks in your existing script.
#
# Two root causes addressed:
#   1. Unquoted $json expansions — shell glob-expands * and ? in cron/JSON
#   2. Unsafe string interpolation inside jq filters — use --arg instead
###############################################################################


# =============================================================================
# FIX 1: Initial JSON read and field extraction
# =============================================================================
# BEFORE:
#   json=$(cat $filename)
#   jobName=$(cat $filename | jq -r .jobconfig.name)
#   aclpermission=$(echo $json | jq -r ".aclpermission")
#   patsecretname=$(echo $json | jq -r ".machineuserpatsecret")
#
# AFTER:

json=$(cat "$filename")
jobName=$(echo "$json" | jq -r '.jobconfig.name')
aclpermission=$(echo "$json" | jq -r '.aclpermission')
patsecretname=$(echo "$json" | jq -r '.machineuserpatsecret')
echo "jobName: $jobName"


# =============================================================================
# FIX 2: Client ID / Secret extraction
# =============================================================================
# BEFORE:
#   clientid=$(cat $filename | jq -r .spdetails.kvclientid)
#   clientsecret=$(cat $filename | jq -r .spdetails.kvclientsecret)
#
# AFTER:

clientid=$(echo "$json" | jq -r '.spdetails.kvclientid')
clientsecret=$(echo "$json" | jq -r '.spdetails.kvclientsecret')


# =============================================================================
# FIX 3: Existing cluster name extraction
# =============================================================================
# BEFORE:
#   existing_cluster_name=$(echo $json | jq -r ".jobconfig.tasks[] | .existing_cluster_id")
#
# AFTER:

existing_cluster_name=$(echo "$json" | jq -r '.jobconfig.tasks[] | .existing_cluster_id')
echo "$existing_cluster_name"


# =============================================================================
# FIX 4: Policy ID lookup and injection
# =============================================================================
# BEFORE:
#   policyId=$(echo $policyList | jq -r ".policies[] | select(.name == \"$PolicyName\") | .policy_id")
#   echo "json: $json"
#   json=$(echo $json | jq -r ".jobconfig")
#   if [[ "$(jq 'has("job_clusters")' <<< $json)" == "true" ]]
#   then
#       json=$(echo $json | jq -r ".job_clusters[].new_cluster += {policy_id: \"$policyId\"}")
#   else
#       json=$(echo $json | jq -r ".tasks[].new_cluster += {policy_id: \"$policyId\"}")
#   fi
#
# AFTER:

if [[ "$existing_cluster_name" = *"null"* ]]
then
    policyId=$(echo "$policyList" | jq -r --arg name "$PolicyName" '.policies[] | select(.name == $name) | .policy_id')
    echo "json: $json"
    json=$(echo "$json" | jq '.jobconfig')

    if [[ "$(jq 'has("job_clusters")' <<< "$json")" == "true" ]]
    then
        json=$(echo "$json" | jq --arg pid "$policyId" '.job_clusters[].new_cluster += {policy_id: $pid}')
    else
        json=$(echo "$json" | jq --arg pid "$policyId" '.tasks[].new_cluster += {policy_id: $pid}')
    fi
else
    # =========================================================================
    # FIX 5: Existing cluster ID lookup and assignment
    # =========================================================================
    # BEFORE:
    #   clusterId=$(echo $clusterList | jq -r ".clusters[] | select(.cluster_name == \"$existing_cluster_name\") | .cluster_id")
    #   json=$(echo $json | jq -r ".tasks[].existing_cluster_id = \"$clusterId\"")
    #
    # AFTER:

    clusterId=$(echo "$clusterList" | jq -r --arg cname "$existing_cluster_name" '.clusters[] | select(.cluster_name == $cname) | .cluster_id')

    # Check for error
    if [ "$clusterId" = "" ];
    then
        echo "ERROR: The job specifies an existing cluster name of ($existing_cluster_name), but no cluster with that name was found in the Databricks workspace."
        exit 1;
    else
        echo "Setting existing_cluster_id"
        json=$(echo "$json" | jq --arg cid "$clusterId" '.tasks[].existing_cluster_id = $cid')
    fi
fi


# =============================================================================
# FIX 6: Schedule / pause status
# =============================================================================
# BEFORE:
#   schedule=$(echo $json | jq -r .schedule)
#   if [[ "$schedule" != "null" ]]
#   then
#       if [ "$env" = "prd" ]
#       then
#           json=$(echo $json | jq -r ".schedule.pause_status = \"UNPAUSED\"")
#       fi
#   fi
#
# AFTER:

schedule=$(echo "$json" | jq -r '.schedule')
if [[ "$schedule" != "null" ]]
then
    if [ "$env" = "prd" ]
    then
        json=$(echo "$json" | jq '.schedule.pause_status = "UNPAUSED"')
    fi
fi


# =============================================================================
# FIX 7: Final job creation call (no change — confirming quoting is correct)
# =============================================================================

create_or_reset_job "$json" "$aclpermission" "$clientid" "$clientsecret" "$accessToken" "$accessTokenkv" "$managementToken" \
    "$workspaceUrl" "$azure_databricks_resource_id" "$resourceId" "$workspaceflag" "$patsecretname"
