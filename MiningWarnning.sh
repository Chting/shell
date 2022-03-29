#ecs可疑文件检测用钉钉报警
#!/bin/bash
PutLog="/root/zhaowl/checklog"
CMD="ls -l"
FileList="/tmp/1 /tmp/log_rot /tmp/.c /autom.sh /ubuntu  /tmp/myip.txt /usr/bin/aliynd-upd-service"

function SendMessageToDingding(){
    Dingding_Url="https://oapi.dingtalk.com/robot/send?access_token=654852835"
    # 发送钉钉消息
    curl "${Dingding_Url}" -H 'Content-Type: application/json' -d "
    {
        \"actionCard\": {
            \"title\": \"可能存在入侵\", 
            \"text\": \"可能存在入侵，请立刻检查！！！\", 
            \"hideAvatar\": \"0\", 
            \"btnOrientation\": \"0\", 
            \"btns\": [
                {
                    \"title\": \"入侵告警\", 
                    \"actionURL\": \"\"
                }
            ]
        }, 
        \"msgtype\": \"actionCard\"
    }"
}

> ${PutLog}

for file in ${FileList}
do
   ansible -i ip_list_all  -m shell -a "${CMD} ${file}" all | egrep -v 'FAILED|No such file or directory' >> ${PutLog}
done

if [ -s ${PutLog} ]; then
    SendMessageToDingding "可能存在入侵，请立刻检查！！！"
    exit 255
fi
