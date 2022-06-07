#!/bin/bash

if [[ $ACCOUNT_SECRET_PHRASE = "" ]]; then
    ACCOUNT_SECRET_PHRASE="$(grep ACCOUNT_SECRET_PHRASE config.txt | cut -c 23-)"
fi

if [[ $NODE_PATH = "" ]]; then
    NODE_PATH="$(grep NODE_PATH config.txt | awk '{ print $2 }')"
fi

if [[ $NODE_CHAIN = "" ]]; then
    NODE_CHAIN="$(grep NODE_CHAIN config.txt | awk '{ print $2 }')"
fi

if [[ $NODE_MODE = "" ]]; then
    NODE_MODE="$(grep NODE_MODE config.txt | awk '{ print $2 }')"
fi

if [[ $NODE_NAME = "" ]]; then
    NODE_NAME="$(grep NODE_NAME config.txt | awk '{ print $2 }')"
fi

if [[ $NODE_DATABASE_PATH = "" ]]; then
    NODE_DATABASE_PATH="$(grep NODE_DATABASE_PATH config.txt | awk '{ print $2 }')"
fi

if [[ $NODE_PRIVATE_KEY = "" ]]; then
    NODE_PRIVATE_KEY="$(grep NODE_PRIVATE_KEY config.txt | awk '{ print $2 }')"
fi

if [[ $SERVICE_FILE_NAME = "" ]]; then
    SERVICE_FILE_NAME="$(grep SERVICE_FILE_NAME config.txt | awk '{ print $2 }')"
fi


function generate_service_file() {
    local exec_start=$NODE_PATH
    exec_start+=" --name $NODE_NAME "
    exec_start+=" --chain $NODE_CHAIN"
    exec_start+=" --base-path $NODE_DATABASE_PATH"
    exec_start+=" --ws-max-connections 1000"
    exec_start+=" --prometheus-port 9615"

    if ! [[ $NODE_PRIVATE_KEY = "" ]]; then
        exec_start+=" --node-key $NODE_PRIVATE_KEY"
    fi

    local node_type="validator"
    if [[ $NODE_MODE == 0 ]]; then 
        exec_start+=" --validator"
    else
        exec_start+=" --pruning archive"
        exec_start+=" --ws-external --rpc-external --rpc-cors all"
        node_type="public"
    fi

    echo "[Unit]" > "$SERVICE_FILE_NAME"
    echo "Description=Ternoa $node_type Node By Ternoa.com" >> "$SERVICE_FILE_NAME"
    echo "" >> "$SERVICE_FILE_NAME"
    echo "[Service]" >> "$SERVICE_FILE_NAME"
    echo "ExecStart=$exec_start" >> "$SERVICE_FILE_NAME"
    echo "WorkingDirectory=/usr/bin" >> "$SERVICE_FILE_NAME"
    echo "KillSignal=SIGINT" >> "$SERVICE_FILE_NAME"
    echo "User=root" >> "$SERVICE_FILE_NAME"
    echo "Restart=on-failure" >> "$SERVICE_FILE_NAME"
    echo "LimitNOFILE=10240" >> "$SERVICE_FILE_NAME"
    echo "SyslogIdentifier=ternoa-$node_type" >> "$SERVICE_FILE_NAME"
    echo "" >> "$SERVICE_FILE_NAME"
    echo "[Install]" >> "$SERVICE_FILE_NAME"
    echo "WantedBy=multi-user.target" >> "$SERVICE_FILE_NAME"
    echo "" >> "$SERVICE_FILE_NAME"

    mkdir -p generated
    cp "$SERVICE_FILE_NAME" "generated/$SERVICE_FILE_NAME"
    rm "$SERVICE_FILE_NAME"

    read -p "Display file content? [Y/n]: " res;
    if [[ $res = "" || $res = "Y" ]]; then
        echo "$(cat generated/$SERVICE_FILE_NAME)"
    fi

    read -p "Move file to /etc/systemd/system? [Y/n]: " res;
    if [[ $res = "" || $res = "Y" ]]; then 
        cp "generated/$SERVICE_FILE_NAME" /etc/systemd/system/
        echo "Done"
    fi

    return 0
} 

function generate_author_keys() {
    node_running;
    local node_run=$RET_VAL
    if [[ $node_run = false ]]; then
        echo "Node is not running, cannot generate author keys. Exiting"
        return 0
    fi

    mkdir -p generated
    curl -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}' http://localhost:9933 &> generated/author_keys.txt

    echo "In order ensure that the keys are used, the node needs to be restarted."
    read -p "Do you want to restart the node now? [Y/n]: " res
    if [[ $res = "" || $res = "Y" ]]; then 
        echo "Restarting node..."
        stop_node
        sleep 2
        start_node
        echo "Node restarted!"
    fi

    return 0
}

function insert_author_keys_from_seed() {
    if [[ $ACCOUNT_SECRET_PHRASE = "" ]]; then
        echo "Environment vairable ACCOUNT_PHRASE is not set. Exiting."
        return 0
    fi

    echo "Insertion type: "
    echo "1 - Cold: Using node insert command"
    echo "2 - Warm: Using rpc calls (Default)"
    read -p "Answer: " res;

    node_running;
    local node_run=$RET_VAL
    if [[ $res = "2" || $res = "" ]]; then 
        if [[ $node_run = false ]]; then
            echo "Node is not running, cannot insert author keys. Exiting"
            return 0
        fi

        echo "Inserting Warm Author keys..."
        local sr_id="$($NODE_PATH key inspect $ACCOUNT_SECRET_PHRASE | grep "Account ID:" | awk '{ print $3 }')"
        local ed_id="$($NODE_PATH key inspect --scheme "Ed25519" $ACCOUNT_SECRET_PHRASE | grep "Account ID:" | awk '{ print $3 }')"

        curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"author_insertKey\",\"params\": [\"gran\",\"$ACCOUNT_SEED\",\"$ed_id\"]}"
        curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"author_insertKey\",\"params\": [\"babe\",\"$ACCOUNT_SEED\",\"$sr_id\"]}"
        curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"author_insertKey\",\"params\": [\"imon\",\"$ACCOUNT_SEED\",\"$sr_id\"]}"
        curl http://localhost:9933 -H "Content-Type:application/json;charset=utf-8" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"author_insertKey\",\"params\": [\"audi\",\"$ACCOUNT_SEED\",\"$sr_id\"]}"
    elif [[ $res = "1"  ]]; then
        echo "Inserting Cold Author keys..."
        $NODE_PATH key insert --chain $NODE_CHAIN -d $NODE_DATABASE_PATH --key-type gran --scheme Ed25519 --suri "$ACCOUNT_SECRET_PHRASE"
        $NODE_PATH key insert --chain $NODE_CHAIN -d $NODE_DATABASE_PATH --key-type babe --scheme Sr25519 --suri "$ACCOUNT_SECRET_PHRASE"
        $NODE_PATH key insert --chain $NODE_CHAIN -d $NODE_DATABASE_PATH --key-type imon --scheme Sr25519 --suri "$ACCOUNT_SECRET_PHRASE"
        $NODE_PATH key insert --chain $NODE_CHAIN -d $NODE_DATABASE_PATH --key-type audi --scheme Sr25519 --suri "$ACCOUNT_SECRET_PHRASE"
    else
        echo "Uknown option."
        return 0
    fi
    echo "Keys successfully inserted."

    if [[ $node_run = true ]]; then
        echo "In order ensure that the keys are used, the node needs to be restarted."
        echo "Do you want to restart the node now? [Y/n]: " res
        if [[ $res = "" || $res = "Y" ]]; then 
            echo "Restarting node..."
            stop_node
            sleep 2
            start_node
            echo "Node restarted!"
        fi
    fi

    return 0
}

# ---- SYSTEM ----
function node_running() {
    ps -aux | grep ternoa | grep -v ssh | grep -v grep
    [[ $? = 0 ]] && RET_VAL=true || RET_VAL=false
}
function stop_node() {
    systemctl stop $SERVICE_FILE_NAME
    return 0
}
function start_node() {
    systemctl start $SERVICE_FILE_NAME
    return 0
}
function enable_node() {
    systemctl enable $SERVICE_FILE_NAME
    return 0
}
#// ---- SYSTEM ----

# ---- ACCOUNTS ----
function generate_account() {
    echo "Geration type: "
    echo "1 - Basic: Only the root Sr25519 account"
    echo "2 - Advanced: The root, Sr25519 stash and the Ed25519 account (default)"
    read -p "Answer: " res;

    if [[ $res = "2" || $res = "" ]]; then 
        generate_account_detailed
    elif [[ $res = "1"  ]]; then
        mkdir -p generated
        $NODE_PATH key generate -w 24 > generated/account_details.txt
    else
        echo "Uknown option."
        return 1
    fi

    return 0
}

function generate_account_detailed() {
    local output="$("$NODE_PATH" key generate -w 24)"
    ACCOUNT_SECRET_PHRASE="$(echo "$output" | grep "Secret phrase:" | cut -c 22-)"
    
    mkdir -p generated
    local file_path=generated/account_details.txt

    # Controller (Sr25519) Account: 
    echo "// Controller (Sr25519) Account: " > $file_path
    echo ""$NODE_PATH" key generate -w 24" >> $file_path
    echo "$output" >> $file_path
    echo "" >> $file_path

    # Stash (Sr25519) Account: 
    echo "// Stash (Sr25519) Account: " >> $file_path
    echo "$NODE_PATH key inspect $ACCOUNT_SECRET_PHRASE//stash" >> $file_path
    $NODE_PATH key inspect "$ACCOUNT_SECRET_PHRASE//stash" >> $file_path
    echo "" >> $file_path

    # Controller (Ed25519) Account: 
    echo "// Controller (Ed25519) Account: " >> $file_path
    echo "$NODE_PATH key inspect --scheme Ed25519  $ACCOUNT_SECRET_PHRASE" >> $file_path
    $NODE_PATH key inspect --scheme Ed25519  "$ACCOUNT_SECRET_PHRASE" >> $file_path
    echo "" >> $file_path

    return 0
}
#// ---- ACCOUNTS ----

function generate_node_keys() {
    mkdir -p generated

    subkey generate-node-key --file generated/node_private_key.txt &> generated/node_public_key.txt
    NODE_PRIVATE_KEY="$(cat generated/node_private_key.txt)"

    return 0
}

function help() {
       # Display Help
   echo "Ternoa tool."
   echo
   echo "Syntax: main.sh [sub-command]"
   echo "sub-commands:"
   echo "      generate-account"
   echo "      generate-node-key"
   echo "      generate-author-keys"
   echo "      insert-author-keys"
   echo "      load-service-file"
   echo "      start-node"
   echo "      stop-node"
}

if [[ -z $1 ]]; then
    help
    exit 0
fi

command=$1
if [[ $1 = "generate-account" ]]; then
    generate_account
    if [[ $? = 0 ]]; then
        echo "Account details exported to generated/account_details.txt" 
    fi 
fi

if [[ $command = "generate-node-key" ]]; then
    generate_node_keys
    if [[ $? = 0 ]]; then
        echo "Node keys exported to generated/node_public_key.txt and generated/node_private_key.txt"
    fi
fi

if [[ $command = "generate-author-keys" ]]; then
    generate_author_keys
    if [[ $? = 0 ]]; then
        echo "Author keys exported to generated/author_keys.txt"
    fi
fi

if [[ $command = "insert-author-keys" ]]; then
    insert_author_keys_from_seed
    if [[ $? = 0 ]]; then
        echo "Account keys have been inserted!"
    fi
fi

if [[ $command = "load-service-file" ]]; then
    generate_service_file
    if [[ $? = 1 ]]; then
        echo "Failed to load service file"
    fi

    if [[ $? = 0 ]]; then
        echo "Service file loaded :D "
    fi
fi

if [[ $command = "start-node" ]]; then
    start_node
fi

if [[ $command = "stop-node" ]]; then
    stop_node
fi
