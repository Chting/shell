#!/usr/bin/bash
#分表执行SQL的脚本
#CMD="mysql -P3306 -hxxxxx -uxxxxx -pxxxxx"
CMD="mysql -P6033 -h172.17.115.220 -uroot -pxxxxx"
DB="redpack"
Table="redpack_info_"
for ((i=0;i<=99;i++))
do
     echo "$i"
       $CMD -e "
ALTER TABLE ${DB}.${Table}${i} 
add is_hidden tinyint(3) unsigned NOT NULL DEFAULT 0 COMMENT '是否隐藏';
"
done
