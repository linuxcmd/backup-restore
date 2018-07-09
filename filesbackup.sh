#!/bin/bash
#script to create backup of wp-content
file="/var/wp-content"
date=`date +"%Y-%m-%d_%H-%M-%S"`
dbname=bovapingwp
backup () {
#Generating files backup and copying it to S3 bucket
tar -czf /nfs-backuup/files/wp-content-$date.tar.gz $file && aws s3 cp /nfs-backuup/files/wp-content-$date.tar.gz s3://bovaping-backups/files/
#Generating db bakups and copying it to S3 bucket
mysqldump $dbname | gzip > /nfs-backuup/mysql/$dbname-$date.sql.gz && aws s3 cp /nfs-backuup/mysql/$dbname-$date.sql.gz s3://bovaping-backups/mysqlbackups/
}
cleanup () {
#removing backup files older than 7 days.
find /nfs-backuup/files/ -type f -iname wp-content-*.tar.gz -mtime +7 -exec rm -rf {} \;
find /nfs-backuup/mysql/ -type f -iname $dbname-*.sql.gz -mtime +7 -exec rm -rf {} \;
}
restore () {
echo "==============================================================================="
printf "1. Local restore. \n2. Restore from S3\n3. Exit\n"
echo "==============================================================================="
read -p "Select an option:" sel
case $sel in
		1) echo "Available file backups are:"
			ls -l /nfs-backuup/files/ | awk '{print $9}'
			read -p "Select a backup file: " optfile
			echo $optfile
			rm -rf $file-original && mv $file{,-original} && mkdir $file
			chown apache. $file
			tar --same-owner -zxf /nfs-backuup/files/$optfile --strip 2 -C $file && echo "Restored files to $file"
			echo "Available DB backups are:"
			ls -l /nfs-backuup/mysql/ | awk '{print $9}'
			read -p "Select a database dump: " optdb
			echo $optdb
			mysql -e "drop database ${dbname}; create database ${dbname}"
			gunzip < /nfs-backuup/mysql/$optdb | mysql $dbname && echo "Restored $optdb to $dbname"
			exit
			;;
		2) echo "Available files backups are: "
			aws s3 ls s3://bovaping-backups/files/ | awk '{ print $4}'
			read -p "Select a backup file: " optfile
			echo $optfile
			if [ -d != /nfs-backuup/export_from_s3 ]
				then
				mkdir -p /nfs-backuup/export_from_s3
			fi
			aws s3 cp s3://bovaping-backups/files/$optfile /nfs-backuup/export_from_s3/
			rm -rf $file-original && mv $file{,-original} && mkdir $file
			chown apache. $file
			tar --same-owner -zxf /nfs-backuup/export_from_s3/$optfile --strip 2 -C $file && echo "Restored files to /var/wp-content"
			echo "Available DB backups are: "
			aws s3 ls s3://bovaping-backups/mysqlbackups/ | awk '{ print $4}'
			read -p "Select a database dump: " optdb
			echo $optdb
			aws s3 cp s3://bovaping-backups/mysqlbackups/$optdb /nfs-backuup/export_from_s3/
			mysql -e "drop database ${dbname}; create database ${dbname}"
			gunzip < /nfs-backuup/export_from_s3/$optdb | mysql $dbname && echo "Restored $optdb to $dbname"
			exit
			;;
		*) echo "Select a valid option"
			exit
			;;
esac
}
		
if [ $1 == create_backups ]
	then
		backup && cleanup
		exit
elif [ $1 == restore_backups ]
	then
		restore && rm -rf /nfs-backuup/export_from_s3/*
		exit
else 
	echo "Script Usage: scriptname create_backups|restore_backups"
	echo 'eg: To create backups run: 	script create_backups'
	exit
fi
