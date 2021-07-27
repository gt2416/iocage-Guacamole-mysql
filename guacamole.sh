#!/bin/sh

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Intro
echo
echo
echo "Welcome to a guacamole install script for TrueNAS Core 12."
echo "This script does not check if you enter invalid entries, please type carefully."
echo
echo "If you do not enter a variable when asked, a default one will be used"
echo "You can cancel the script anytime with CTRL+C"
sleep 1
echo
echo

########### Get configuration variables from user ###########

# jailName
read -p "What do you want the jail to be called? (default:guacamole):" jailName
if [ -z "${jailName}" ]; then
  echo 'Warning: Jail Name not set.'
  echo 'Using default: guacamole'
  jailName="guacamole"
  fi
sleep .5
  
# IP  
echo
read -p "What's the IP of the jail? (default:192.168.1.56):" IP
if [ -z "${IP}" ]; then
  echo 'Warning: IP not set !! (this is probably bad).'
  echo 'Using default: 192.168.1.56'
  IP="192.168.1.56"
  fi
 sleep .5
  
# Gateway IP
echo
read -p "What's the IP of the gateway? (default:192.168.1.1):" gIP
if [ -z "${gIP}" ]; then
  echo 'Warning: Gateway IP not set !! (this is probably bad).'
  echo 'Using default: 192.168.1.1'
  gIP="192.168.1.1"
  echo
  fi
sleep .5

# Database name
echo
read -p "Database name ? (default:guacDb):" dbName
if [ -z "${dbName}" ]; then
  echo 'Warning: SQL database name not set'
  echo 'Using default: guacDb'
  dbName="guacDb"
  echo
  fi
sleep .5 

# Database User
echo
read -p "What do you want your SQL user to be called? (default:guacUser):" dbUser
if [ -z "${dbUser}" ]; then
  echo 'Warning: SQL user not set'
  echo 'Using default: guacUser'
  dbUser="dbUser" 
  echo
  fi
sleep .5
 
# Database user password
echo
read -p "Database user's password ? (default:password):" dbPass
if [ -z "${dbPass}" ]; then
  echo 'Warning: SQL password not set'
  echo 'Using default: password'
  dbPass="password" 
  echo
  fi
sleep .5 

echo 'Ok. I have everything I need (hopefully).'
echo
echo 'Jail Name='$jailName
echo 'Jail IP='$IP
echo 'Router IP='$gIP
echo 'Database Name='$dbName
echo 'Database User='$dbUser 
echo 'Database Password='$dbPass 
echo
read -p 'Shall I continue ? (y/n):' yn
if [ "${yn}" = "n" ]; then 
	echo 'Ok, bye.'
	exit 1
	fi
	
########### Create the jail and setup guacamole ###########

echo 'Creating the jail.'
sleep .5

iocage create -n "${jailName}" -r 12.2-RELEASE ip4_addr="vnet0|${IP}/24" defaultrouter=""${gIP}"" vnet="on" allow_raw_sockets="1" boot="on"

echo
echo 'Setting up the jail and guacamole'
sleep 1
iocage exec "${jailName}" pkg install -y nano git guacamole-client mariadb105-server
iocage exec "${jailName}" sysrc guacd_enable=yes
iocage exec "${jailName}" sysrc tomcat9_enable=yes
iocage exec "${jailName}" sysrc mysql_enable=yes

iocage exec "${jailName}" mkdir -p /usr/local/etc/guacamole-client/extensions
iocage exec "${jailName}" mkdir -p /usr/local/etc/guacamole-client/lib

iocage exec "${jailName}" service mysql-server start

echo
echo 'Creating Database'
sleep 2
iocage exec "${jailName}" mysql -u root -e "CREATE DATABASE ${dbName};"
sleep 1
iocage exec "${jailName}" mysql -u root -e "CREATE USER '${dbUser}'@'localhost' IDENTIFIED BY '${dbPass}';"
sleep 1
iocage exec "${jailName}" mysql -u root -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ${dbName}.* TO ${dbUser}@localhost;"
sleep 1
iocage exec "${jailName}" mysqladmin --user=root password reload

echo
echo 'Done, fetching guacamole sql files'
iocage exec "${jailName}" fetch -o /tmp https://downloads.apache.org/guacamole/1.3.0/binary/guacamole-auth-jdbc-1.3.0.tar.gz
iocage exec "${jailName}" tar xvf /tmp/guacamole-auth-jdbc-1.3.0.tar.gz -C /tmp/
iocage exec "${jailName}" cp -f /tmp/guacamole-auth-jdbc-1.3.0/mysql/guacamole-auth-jdbc-mysql-1.3.0.jar /usr/local/etc/guacamole-client/extensions/
echo
echo 'When it asks for a password just press enter to continue'
echo
iocage exec "${jailName}" "cat /tmp/guacamole-auth-jdbc-1.3.0/mysql/schema/*.sql | mysql -u root -p $dbName"

iocage exec "${jailName}" fetch -o /tmp https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.26.tar.gz
iocage exec "${jailName}" tar xvf /tmp/mysql-connector-java-8.0.26.tar.gz -C /tmp/
iocage exec "${jailName}" cp -f /tmp/mysql-connector-java-8.0.26/mysql-connector-java-8.0.26.jar /usr/local/etc/guacamole-client/lib/

iocage exec "${jailName}" touch /usr/local/etc/guacamole-client/guacamole.properties
iocage exec "${jailName}" "echo '# MySQL properties' >> /usr/local/etc/guacamole-client/guacamole.properties"
iocage exec "${jailName}" "echo 'mysql-hostname: localhost' >> /usr/local/etc/guacamole-client/guacamole.properties"
iocage exec "${jailName}" "echo 'mysql-port: 3306' >> /usr/local/etc/guacamole-client/guacamole.properties"
iocage exec "${jailName}" "echo 'mysql-database: '$dbName >> /usr/local/etc/guacamole-client/guacamole.properties"
iocage exec "${jailName}" "echo 'mysql-username: '$dbUser >> /usr/local/etc/guacamole-client/guacamole.properties"
iocage exec "${jailName}" "echo 'mysql-password: '$dbPass >> /usr/local/etc/guacamole-client/guacamole.properties"

iocage exec "${jailName}" service guacd start
iocage exec "${jailName}" service tomcat9 start 
iocage exec "${jailName}" service mysql-server restart

dbRootPass=$(openssl rand -base64 16)
iocage exec "${jailName}" "mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbRootPass';""

echo 'mysql-database: '$dbName >> /root/guacamole
echo 'mysql-username: '$dbUser >> /root/guacamole
echo 'mysql-password: '$dbPass >> /root/guacamole
echo 'mysql root password for guacamole jail:'$dbRootPass >> /root/guacamole

echo
echo 'All done, check' $IP':8080/guacamole'
echo 'If thats works, login with guacadmin/guacadmin'

echo 'mysql root password for guacamole jail:'$dbRootPass
echo 'All settings are saved in /root/guacamole'