#!/usr/bin/env bash
#mysql从库一键部署
#是否交互
interactive=0
#为空则为当前目录
mysql_instance_base=
read -p "主库链接：" master_host
echo -e "\n"
if [ -z "${master_host}" ];then
 echo "链接不能为空"
        exit 1
fi

#主库mysql版本, 5.6或5.7, 改为自动识别
#master_version=5.7
#从库端口,为空则通过目录自动识别 (识别模式:目录末尾的数字,例如 /data/xxx_3306)
slave_port=

###my.cnf 配置
#为空则取本机"ip:port"的crc32值
server_id=
#如果主库版本为mysql5.6则自动设置为0
slave_parallel_workers=2
#缓存池大小, 按需设置
innodb_buffer_pool_size=2G
#缓存池实例数, 按需设置
innodb_buffer_pool_instances=2


#从库root账号与密码
slave_root_user=slave_root
slave_root_passwd=xxxx
slavip=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"|grep "172.17"`

#主库复制账号
read -p "输入端口：" master_port
echo -e "\n"
if [ -z "${master_port}" ];then
        master_port=3306
fi

read -p "my.cnf文件位置：" mycnfpa
echo -e "\n"
if [ -z "${mycnfpa}" ];then
        echo "不能为空"
fi

read -p "master管理员用户名：" mastroot
echo -e "\n"
if [ -z "${mastroot}" ];then
        echo "不能为空"
fi

#master_port=3306
master_repli_user=zbx_repli
master_repli_passwd=zbx_repli_123


##function list##

function echo_green {
    echo -e "\033[;32m$*\033[0m"
    sleep 0.5
}

function echo_red {
    echo -e "\033[;31m$*\033[0m"
}

function echo_pink {
    echo -e "\033[;35m$*\033[0m"
}

function start_mysql() {
    local extra_params=$*
    echo "sh start.sh ${extra_params}"
    sh start.sh ${extra_params}
    check_and_wait "[[ -f mysqld.pid ]]" 10 "mysql启动 ${extra_params}" "exit 1"
}

function stop_mysql() {
    sh stop.sh
    check_and_wait "[[ ! -f mysqld.pid ]]" 10 "mysql关闭" "exit 1"
}

function get_mysql_version() {
    local conn_info=$*
    ver=$(echo ${conn_info} | grep -Eo '5\.[0-9]?' | tail -1)
    if [[ "${ver}" != "5.6" ]] && [[ "${ver}" != "5.7" ]];then
        return 1
    fi
    echo ${ver}
    return 0
}

function err_exit() {
    local desc=$*
    echo_pink ${desc}
    exit 1
}

function check_and_wait() {
    local check=$1
    local max_wait=$2
    local desc=$3" "
    local err_handle=$4
    for i in $(seq ${max_wait}); do
        eval "${check}"
        local res=$?
        if [[ ${res} != 0 ]];then
            sleep 1
        else
            echo_green "${desc}success!!"
            return 0
        fi
        echo "$i times check \"${check}\""
    done
    echo "$desc $2s timeout"
    if [[ "${err_handle}" != "" ]];then
        eval "${err_handle}"
    fi
    return 1
}

function check_user() {
    local user=$1
    me=$(whoami)
    if [[ "$me" != "$user" ]];then
        return 1
    fi
    return 0
}

#--------

check_user "mysql"
res=$?
if [[ ${res} > 0 ]];then
    err_exit "当前用户为$(whoami), 请切换为mysql用户"
fi



conn_info=$(mysql -h${master_host} -u${master_repli_user} -P${master_port} -p${master_repli_passwd} --connect-timeout=3 -e "select version()")
res=$?
if [[ ${res} > 0 ]];then
    echo_red "mysql -h${master_host} -u${master_repli_user} -P${master_port} -p${master_repli_passwd} --connect-timeout=3"
    err_exit "复制账号连接测试失败, 请检查账号或者IP限制"
else
    echo_green "复制账号连接测试成功"
fi
echo "conn_info:${conn_info}"
master_version=$(get_mysql_version ${conn_info})

if [[ "${master_version}" != "5.6" ]] && [[ "${master_version}" != "5.7" ]];then
    err_exit "主库版本不为5.6或5.7, 暂不支持同步!!"
else
    echo_green "master_version:${master_version}"
    echo_green "复制账号连接测试成功"
    sleep 1
fi

##生成my.cnf
mycnf_template='
[client]
port=${slave_port}
socket=${mysql_instance_base}/mysql.sock
 
[mysql]
bind-address=0.0.0.0
port=${slave_port}
no-auto-rehash
prompt="\\u@\\h:\\p [\\d]> "
default-character-set=utf8mb4
 
[mysqld]
#skip-grant_tables
report_host='${slavip}'
port=${slave_port}
server_id=${server_id}
pid-file=${mysql_instance_base}/mysqld.pid
socket=${mysql_instance_base}/mysql.sock
datadir=${mysql_instance_base}/data
log-error=${mysql_instance_base}/logs/mysqlerror.log
slow_query_log_file=${mysql_instance_base}/logs/slowquery.log
general_log_file=${mysql_instance_base}/logs/general.log
innodb_data_home_dir=${mysql_instance_base}/data
log_bin=${mysql_instance_base}/logs/mysql-bin
innodb_log_group_home_dir=${mysql_instance_base}/data
innodb_buffer_pool_size=${innodb_buffer_pool_size}
innodb_buffer_pool_instances=${innodb_buffer_pool_instances}
innodb_io_capacity = 10000
innodb_io_capacity_max = 20000
tmpdir=/dev/shm
gtid_mode=ON
log-slave-updates=1
enforce_gtid_consistency=ON
slow_query_log=1
long_query_time=1.0
log_slow_admin_statements=0
read_only=1
 
slave_parallel_workers=${slave_parallel_workers}
 
slave_parallel_type=LOGICAL_CLOCK
log_timestamps=SYSTEM
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init_connect="SET NAMES utf8mb4"
lower_case_table_names = 0
skip_name_resolve = 1
open_files_limit = 65535
back_log = 512
binlog_cache_size=2M
max_binlog_cache_size=10G
max_binlog_size=500M
binlog-format=ROW
 
expire_logs_days=2
sync_binlog=100
log_slave_updates=1
 
large_pages=ON
max_connections = 5000
max_user_connections=3000
max_connect_errors = 100000
sql_mode=
max_allowed_packet = 200M
transaction-isolation=REPEATABLE-READ
tmp_table_size=64M
innodb_thread_concurrency=0
innodb_open_files=65536
innodb_file_per_table=1
innodb_change_buffering=inserts
innodb_adaptive_flushing=1
innodb_old_blocks_time=1000
innodb_stats_on_metadata=0
innodb_use_native_aio=1
innodb_lock_wait_timeout=5
innodb_rollback_on_timeout=1
innodb_strict_mode=1
innodb_disable_sort_file_cache=ON
innodb_sync_array_size=16
innodb_print_all_deadlocks=1
innodb_sync_spin_loops = 100
innodb_spin_wait_delay = 30
innodb_log_file_size=256M
innodb_log_buffer_size=32M
innodb_change_buffering=all
innodb_flush_log_at_trx_commit=2
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_at_shutdown = 1
innodb_log_files_in_group = 2
innodb_max_undo_log_size = 4G
innodb_flush_neighbors = 0
innodb_read_io_threads=6
innodb_write_io_threads=2
innodb_purge_threads = 2
innodb_page_cleaners = 2
innodb_open_files = 65535
innodb_max_dirty_pages_pct=60
innodb_max_dirty_pages_pct_lwm=10
innodb_flush_method = O_DIRECT
innodb_lru_scan_depth = 4000
innodb_checksums = 1
innodb_checksum_algorithm = crc32
innodb_online_alter_log_max_size = 4G
internal_tmp_disk_storage_engine = InnoDB
innodb_stats_on_metadata = 0
innodb_status_file = 1
innodb_status_output = 0
innodb_status_output_locks = 0
rpl_stop_slave_timeout=600
master_verify_checksum=OFF
sort_buffer_size=848K
thread_stack=512K
thread_cache_size=256
read_rnd_buffer_size=432K
join_buffer_size=128K
read_buffer_size=848K
skip-name-resolve
skip-ssl
connect_timeout=10
net_read_timeout=30
net_write_timeout=30
thread_handling=one-thread-per-connection
log_bin_trust_function_creators=ON
'


if [[ "${mysql_instance_base}" == "" ]];then
    mysql_instance_base=$(cd `dirname $0`; pwd)
fi

if [[ "${slave_port}" == "" ]];then
    slave_port=${mysql_instance_base##*_}
    echo ${slave_port} | grep -Eq  '^[0-9]+$'
    if [[ $? > 0 ]];then
        err_exit "my.cnf端口号配置错误"
    fi
fi

if [[ ${server_id} == "" ]];then
    ip=$(ifconfig eth0 | grep inet | awk '{print $2}')
    if [[ ${ip} == "" ]] || [[ ${ip} == "127.0.0.1" ]];then
        ip=$RANDOM
    fi
    echo_green "ip:port -> ${ip}:${slave_port}"
    server_id=$(echo "${ip}:${slave_port}" | cksum | awk '{print $1}')
fi

if [[ "${master_version}" == "5.6" ]];then
    slave_parallel_workers=0
fi

echo "slave_port:${slave_port}"
echo "mysql_instance_base:${mysql_instance_base}"
echo "server_id:${server_id}"
echo "slave_parallel_workers:${slave_parallel_workers}"
echo "innodb_buffer_pool_size:${innodb_buffer_pool_size}"
echo "innodb_buffer_pool_instances:${innodb_buffer_pool_instances}"

if [[ ${interactive} > 0 ]];then
read -r -p "是否确定以上配置, 并继续? [y/n] " input
    case ${input} in
    [yY][eE][sS]|[yY])
        :
        ;;
    [nN][oO]|[nN])
        err_exit "退出"
        ;;
        *)
        err_exit "Invalid input..."
        ;;
    esac
fi

mycnf_template=${mycnf_template//\$\{slave_port\}/${slave_port}}
mycnf_template=${mycnf_template//\$\{mysql_instance_base\}/${mysql_instance_base}}
mycnf_template=${mycnf_template//\$\{server_id\}/${server_id}}
mycnf_template=${mycnf_template//\$\{slave_parallel_workers\}/${slave_parallel_workers}}
mycnf_template=${mycnf_template//\$\{innodb_buffer_pool_size\}/${innodb_buffer_pool_size}}
mycnf_template=${mycnf_template//\$\{innodb_buffer_pool_instances\}/${innodb_buffer_pool_instances}}

echo "${mycnf_template}" > my.cnf



#初始化

if [[ "${mysql_instance_base}" == "" ]];then
    mysql_instance_base=$(cd `dirname $0`; pwd)
fi

echo_green "data dir:${mysql_instance_base}"

if [[ ! -d ${mysql_instance_base} ]];then
  mkdir -p ${mysql_instance_base}
fi

if [[ ! -d ${mysql_instance_base} ]];then
  err_exit "创建数据目录失败, 请检查权限!"
fi

cd ${mysql_instance_base}

rm -rf ${mysql_instance_base}/data
rm -rf ${mysql_instance_base}/logs

#mysql数据解压目录
if [[ ! -d data ]];then
  mkdir data
fi

#mysql日志目录
if [[ ! -d logs ]];then
  mkdir logs
fi

#mysql启动脚本
echo '#/bin/bash
home_dir=$(cd `dirname $0`; pwd)
extra_params=$*
#mysqld --defaults-file=my.cnf &
mysqld --defaults-file=${home_dir}/my.cnf  $extra_params &
 
' > start.sh

#mysql停止脚本
echo '#/bin/bash
kill `cat mysqld.pid`
 
'> stop.sh



##----download-----
#DIRS="$( cd "$( dirname "$0"  )" && pwd  )" 
#echo "${DIRS}"
sshpass -p '111' ssh ${master_host} " innobackupex  --defaults-file=${mycnfpa} --host=${master_host} --user=${master_repli_user} --port=${master_port} --password=${master_repli_passwd} --no-timestamp --slave-info /mnt/${master_host}-${master_port} "
mkdir data
sshpass -p '111' scp -r ${master_host}:/mnt/${master_host}-${master_port}/* ./data/
echo_green "innobackupex 恢复数据..."
innobackupex --defaults-file=data/backup-my.cnf --apply-log  ./data
#innobackupex --defaults-file=./my.cnf --force-non-empty-directories --copy-back ./data

if [[ $? > 0 ]];then
    err_exit "innobackupex 恢复数据失败"
fi

#---


echo_green "master mysql版本为:${master_version}"
start_mysql --skip-grant_tables
if [[ "${master_version}" == "5.6" ]];then
    echo "执行mysql_upgrade..."
    mysql_upgrade -uroot -h127.0.0.1 -P"${slave_port}" -p${slave_root_passwd}
    stop_mysql
    start_mysql --skip-grant_tables
fi

##----
echo_green "修改表引擎..."
echo_green "修改${slave_root_user}密码..."

mysql -uroot -h127.0.0.1 -P"${slave_port}" -e "\
show databases;
set sql_mode='';
use mysql;
alter table proc ENGINE = myisam;
alter table func ENGINE = myisam;
alter table event ENGINE = myisam;
FLUSH PRIVILEGES;
select '修改root...';
ALTER USER '${mastroot}'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'xxx';
select '修改root用户名...';
RENAME USER '${mastroot}'@'%' TO 'xxx_root'@'%';
FLUSH PRIVILEGES;
" -f
stop_mysql
start_mysql

echo_green "设置默认账号"
mysql -ualiyun_root -h127.0.0.1 -P"${slave_port}" -p${slave_root_passwd} -e "\
CREATE USER 'read_only'@'%' IDENTIFIED BY 'xxxx';
GRANT SELECT, SHOW DATABASES ON *.* TO 'read_only'@'%';
CREATE USER 'write_xx'@'%' IDENTIFIED BY 'xxxx';
GRANT CREATE ROUTINE, CREATE VIEW, ALTER, SHOW VIEW, CREATE, ALTER ROUTINE, EVENT, SUPER, INSERT, RELOAD, SELECT, DELETE, FILE, SHOW DATABASES, TRIGGER, PROCESS, REFERENCES, UPDATE, DROP, EXECUTE, CREATE TEMPORARY TABLES, INDEX ON *.* TO 'write_all'@'%';
FLUSH PRIVILEGES;
" -f

if [[ "${master_version}" == "5.6" ]];then
    echo "mysql5.6设置..."
    echo "设置slave_parallel_workers=0"
    mysql -ualiyun_root -h127.0.0.1 -P"${slave_port}" -p${slave_root_passwd} -e "\
    set global slave_parallel_workers=0;
    "
fi

#mysql
#set_gtid=$(cat data/xtrabackup_slave_info| grep SET)
set_gtid=`cat data/xtrabackup_info | tr '\n' ' ' | awk -F 'innodb_from_lsn' '{print $1}'  | awk -F 'last change' '{print $2}'`

echo_green "${set_gtid}"

echo_green "设置同步"
mysql -u${slave_root_user} -h127.0.0.1 -P"${slave_port}" -p${slave_root_passwd} -e "\
stop slave;
reset slave;
reset master;
CHANGE MASTER TO MASTER_AUTO_POSITION=1;
SET GLOBAL gtid_purged=${set_gtid};
CHANGE MASTER TO MASTER_HOST='${master_host}',MASTER_PORT=${master_port},MASTER_USER='${master_repli_user}',MASTER_PASSWORD='${master_repli_passwd}',MASTER_AUTO_POSITION=1,MASTER_HEARTBEAT_PERIOD=2,MASTER_CONNECT_RETRY=1,MASTER_RETRY_COUNT=3;
set global slave_net_timeout=8;
start slave;
select sleep(1);
show slave status\G
"
echo_green "同步执行完毕!!"                                                                 
