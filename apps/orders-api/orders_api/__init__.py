# PyMySQL is a pure-Python MySQL driver: no C build toolchain needed.
# This makes Django's MySQL backend use it in place of mysqlclient.
import pymysql

pymysql.install_as_MySQLdb()
