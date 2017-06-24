#!/bin/bash

source ./test.conf

group=$studentlist

gid=`cat /etc/group | grep ^$group: | cut -d':' -f3`
[ -z $gid ] && echo "No such group:$group" && exit 1

studentlist=`cat /etc/passwd | grep ":$gid:" | cut -d':' -f1`

[ -f studentlist ] && rm studentlist
for student in ${studentlist[@]}
do
	echo $student >> studentlist
	echo $student
done
