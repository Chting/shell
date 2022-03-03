#!/usr/bin/bash
#分库分表执行SQL
CMD="mysql -P3306 -hxxxxx -uxxxx -pxxxx"
DB="orders_"
Table="zk_tbk_order_"
for ((t=0;t<=15;t++))
do
for ((i=0;i<=127;i++))
do
     echo ${DB}${t}.${Table}${i}
        $CMD -e " ALTER TABLE ${DB}${t}.${Table}${i} add index s_idx_adzone_id_create_time (adzone_id,create_time) "
        $CMD -e " ALTER TABLE ${DB}${t}.${Table}${i} add index s_idx_user_id (user_id) "
        $CMD -e " ALTER TABLE ${DB}${t}.${Table}${i} add index s_idx_device_id (device_id) "
done
done
