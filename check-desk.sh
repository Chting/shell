#检测磁盘是否可写并使用飞书报警
#!/bin/bash
dir=`df -h |grep '/data' | awk '{print $6}'`
ips=`hostname -i | sed -e 's/ /\r\n/g' | grep '172.17'`
hostnames=`hostname`
#echo $dir
#echo $ips
for i in $dir
 do

        disks=`df -h |grep "${i}" | awk '{print $1}'`
   dd if=/dev/zero bs=1024 count=10 of=$i/desk-write-check.tmp
        if [ $? -ne 0 ]; then
        curl --location --request POST 'https://open.feishu.cn/open-apis/bot/v2/hook/zzzzzz' \
                --header 'Content-Type: application/json' \
                --data-raw '{
    "msg_type": "post",
    "content": {
        "post": {
            "zh_cn": {
                "title": "",
                "content": [
                    [
                        {
                            "tag": "text",
                            "text": " ecs:'${hostnames}'\n ip:'${ips}' \n 目录'${i}' 不可写！\n 请马上检测挂载磁盘'${disks}'!"
                        },
                        {
                            "tag": "at",
                            "user_id": "all"
                        }
                    ]
                          ]
                     }
                 }
                }
                        }'
        else
         sleep 1
        fi
 done
