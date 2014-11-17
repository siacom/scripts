#!/bin/bash

NC='\e[0m' # No Color
red='\e[0;31m'
green='\e[0;32m'
blue='\e[0;34m'
cyan='\e[0;36m'
yellow='\e[1;33m'
lpurple='\e[1;35m'
purple='\e[0;35m'
lblue='\e[1;34m'
rust='\e[0;33m'

read_var()
{
    arg1=$1
    arg2=$2

    read -t 10 arg1
    if [[ $arg1 = "" ]]; then 
        arg1=$arg2
    fi
    echo $arg1
}

user_input()
{
    # include conditions for specific installations, case statement?

    clear
    echo "Enter current system username"
    read_var currentUser $USER
    clear
    echo "Enter the mysql root password"
    read_var mysqlPasswd default
    clear
    echo "Enter name of initial laravel project"
    read_var laravelProject laravel
    clear
    echo "Enter admin email (e.g. you@domain.com.au)"
    read_var adminEmail admin@$HOSTNAME.local
    clear
    echo "Enter developers full name"
    read_var ownerName $USER
    clear
}

setPermissions()
{
    sudo chown -R $ownerName:websites /srv/www/$laravelProject/
    sudo chmod -R 775 /srv/www/$laravelProject/
    sudo chmod -R 777 /srv/www/$laravelProject/app/storage/
}

update()
{
    echo "Updating System..."
    sleep 1
    sudo apt-get update > /dev/null
    clear
}

restart_service()
{
    case $1 in
        "apache2" )
            sudo service apache2 restart
            sudo service apache2 reload
            ;;
        "placeholder" )
            ;;
    esac
}

base_setup()
{
    echo "Preparing to install Base packages required for further installations..."
    sleep 2
    sudo apt-get install -y vim curl python-software-properties python3.4 java-common nodejs npm git-core
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    clear
}

php_setup()
{
    echo "Preparing to install PHP, MySQL and Apache2 and related apps..."
    sleep 2
    sudo add-apt-repository -y ppa:ondrej/php5
    update
    sudo apt-get install -y php5 apache2 libapache2-mod-php5 php5-curl php5-gd php5-mcrypt 
   
    clear
    #Enabling mod-rewrite
    sudo a2enmod rewrite
    # ---// What developer codes without errors on? Lets turn errors on \\---
    sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php5/apache2/php.ini
    sed -i "s/display_errors = .*/display_errors = On/" /etc/php5/apache2/php.ini
    restart_service apache2

}

xdebug_setup()
{
    echo "Preparing to install Xdebug..."
    sleep 2
    sudo apt-get install -y php5-xdebug
    clear

cat<<EOF
| sudo tee -a /etc/php5/mods-available/xdebug.ini
xdebug.scream=1
xdebug.cli_color=1
xdebug.show_local_vars=1
EOF
    echo "Xdebug installation complete."
    sleep 1
    clear
}

mysql_setup()
{

    # ---// Setting required selections for MySQL and Phpmyadmin installation(s) \\---
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password "$mysqlPasswd""
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password "$mysqlPasswd""
    # Installing mysql server and other related packages
    sudo apt-get install -y mysql-server-5.5 php5-mysql libapache2-mod-auth-mysql

    sudo /etc/init.d/mysql stop
    sudo pkill mysqld
    sudo killall mysqld

    mysqlPasswd='itbuff2121'
    # this is done twice on purpose
    sudo /usr/sbin/mysqld --skip-grant-tables --skip-networking & mysql -u root
    sudo /usr/sbin/mysqld --skip-grant-tables --skip-networking & mysql -u root
    echo "FLUSH PRIVILEGES;"
    echo "SET PASSWORD FOR root@'localhost' = PASSWORD('"$mysqlPasswd"');"
    echo "UPDATE mysql.user SET Password=PASSWORD('"$mysqlPasswd"') WHERE User='root';"
    echo "FLUSH PRIVILEGES;"
    echo "exit"
    sudo mysql_install_db
    sudo /etc/init.d/mysql start

sudo mysql_secure_installation<<EOF
$mysqlPasswd
n
Y
Y
Y
Y
EOF

    restart_service apache2

}

directories_setup()
{
    # ---// Setting up working directories \\---
    echo "Setting up working directories..."
    sleep 2
    sudo mkdir /srv/www
    #Set access rights to main www folder where all sites reside
    sudo chmod -R a+rX /srv/www/
    #Add group called websites
    sudo addgroup websites
    #Add existing user to group
    sudo usermod -a -G websites $currentUser
    #give the group websites full access to www
    sudo chown -R $currentUser:websites /srv/www/
    sudo chmod -R 0775 /srv/www/
    clear
}

phpmyadmin_setup()
{
    echo "Preparing to install phpmyadmin..."
    sleep 2

    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password "$mysqlPasswd""
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password "$mysqlPasswd""
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password "$mysqlPasswd""
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"

    sudo apt-get install -y phpmyadmin
    clear
}

composer_setup()
{
    echo "Preparing to install Composer..."
    sleep 2
    cd ~/Downloads
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    PATH=$PATH:~/.composer/vendor/bin
    clear
}

laravel_setup()
{   
    echo "Your laravel project will be install to /srv/www/projectName, type another path or hit enter to use this default path."
    
    echo "Enter project path."
    read -t 10 projectPath

    if [[ $projectPath = "" ]]; then
        projectPath="/srv/www"
    fi

    cd $projectPath
    echo -e "\nProject path will be: "$projectPath""
    clear

    composer self-update
    echo "Installing latest laravel now..."
    composer global require "laravel/installer=~1.1"
    clear
    if [[ $1 = "standalone" ]]; then
        echo "For latest dev version, type dev and hit enter, otherwise just hit enter."
        read version
        echo "Enter the name of your new laravel project."
        read laravelProject
        case $version in
            "dev" )
                composer create-project laravel/laravel $laravelProject dev-develop;;
            * )
                laravel new $laravelProject;;
        esac
        laravel_conf
        laravel_final
    fi
}

laravel_conf()
{
    # ---// Creation & setup of sites-available project .conf file \\---
    echo "Creating and configuring "$laravelProject".conf file ---"
    sleep 2
    echo "# filename:  "$laravelProject".conf
    # domain:    http://"$laravelProject"
    # DNS Entry: yes, on FS1
    # Public:    No
    # Dev:       Yes
    # Owner:     "$ownerName"
    #
    # VirtualHost settings
    <VirtualHost *:80>
        ServerAdmin "$adminEmail"
        ServerName "$laravelProject"

        DocumentRoot /srv/www/"$laravelProject"/public/

        # Optional Directory index
        DirectoryIndex index.php index.html index.htm

        # Custom log file settings
        LogLevel warn
        ErrorLog  /srv/www/"$laravelProject"/log/error.log
        CustomLog /srv/www/"$laravelProject"/log/access.log combined

        <Directory /srv/www/"$laravelProject"/public/>
        Options All
        AllowOverride All
        Require all granted
        </Directory>
    </VirtualHost>
    " | sudo tee /etc/apache2/sites-available/$laravelProject.conf
    clear
}

laravel_final()
{
    echo "Backing up /etc/hosts file..."
    echo "need to code assigning site to localhost cleanly"
    sleep 2
    sudo cp --backup=numbered /etc/hosts /etc/hosts.backup
    # sed -i "s/localhost.*/localhost "$laravelProject"/" /etc/hosts
    clear

    echo "Enabling "$laravelProject" site for use..."
    sleep 2
    sudo a2ensite $laravelProject
    clear

    sudo mkdir /srv/www/$laravelProject/log
    # ---// Create required directories \\---
    sudo mkdir /srv/www/$laravelProject/app/assets/
    sudo mkdir /srv/www/$laravelProject/app/assets/coffee/
    sudo mkdir /srv/www/$laravelProject/app/assets/sass/
    setPermissions
    echo "Installing Ruby & Sass"
    cd /srv/www/$laravelProject/
    sudo apt-get install -y ruby
    gem install -y sass
}


# ------------// Work in progress \\------------
git_setup()
{
    # ---// Install & Setup Git \\---
    sudo apt-get install -y git
    #Set the default name for Git to use when you commit
    echo "If your name and email for git-hub are different from what was provided earlier press 1 and hit enter"
    read input_var
    if [[ $input_var = "1" ]] ; then
        echo "not implemented yet"
        # run function to ask for ownerName and adminEmail
        # set up the user_input function to take the required arguments
    fi
    if [[ $1 = "standalone" ]] ; then
        echo "Enter your name for git-hub"
        read ownerName
        echo "Enter your associated email for git-hub"
        read adminEmail
    fi
    git config --global user.name $ownerName
    #Set the default email for git to use when you commit
    git config --global user.email $adminEmail
    #Set git to use the credential memory cache
    git config --global credential.helper cache
}

bower_setup()
{
    cd /srv/www/$laravelProject/
    clear
    # ---// Install bower \\---
    echo "Preparing to install Bower..."
    sleep 2
    sudo npm install -g bower
    clear
    echo "Setting up config files..."
    sleep 2
    # ---// create .bowerrc file \\---
    echo '"directory": "public/bootstraps"' | sudo tee /srv/www/$laravelProject/.bowerrc > /dev/null
    # ---// create bower.json to run install \\---
    echo '
{
  "name": "laravel",
  "dependencies": {
    "jquery": "~2.1.1",
    "jquery-ui": "~1.11.0",
    "toastr": "~2.0.3",
    "chart.js": "~0.1.0",
    "bootstrap": "~3.1.1",
    "angular": "~1.2.17",
    "coffee-script": "~1.7.1"
  }
}' | sudo tee /srv/www/$laravelProject/bower.json > /dev/null
    bower install
    clear
    # Change that to specific bower packages for latest version
    # therefore:
    #            bower install jquery -S
    #            bower install jquery-ui -S
    #            bower install toastr -S
    #            bower install angular -S
    #            bower install bootstrap-sass-official -S
    #
    # The file above should include before starting install.
    #  {
    #     "name": "{sitename}",
    #     "dependencies": {
    #     }
    #  }


}

gulp_setup()
{
    # ---// create gulpfile.js  \\---
    echo "
    var gulp = require('gulp');
    var gutil = require('gulp-util');
    var notify = require('gulp-notify');
    var sass = require('gulp-ruby-sass');
    var autoprefixer = require('gulp-autoprefixer');
    var coffee = require('gulp-coffee');
    var exec = require('child_process').exec;
    var sys = require('sys');
     
    var sassdir = 'app/assets/sass';
    var targetCssDir = 'public/css';
     
    var coffeeDir = 'app/assets/coffee';
    var targetJsDir = 'public/js';
     
    gulp.task('css', function() {
        return gulp.src(sassdir + '/main.sass')
            .pipe(sass({ style: 'compressed'}).on('error', gutil.log))
            .pipe(autoprefixer('last 5 version'))
            .pipe(gulp.dest(targetCssDir))
            .pipe(notify({ message: 'CSS compiled, prefixed and minified.'}));
    });
     
    gulp.task('js', function(){
        return gulp.src(coffeeDir + '/**/*.coffee')
            .pipe(coffee().on('error', gutil.log))
            .pipe(gulp.dest(targetJsDir))
            .pipe(notify({ message: 'Coffee Script compiled and minified.'}));;
    });
     
    // Run all PHPUnit tests
    gulp.task('phpunit', function() {
        exec('phpunit', function(error, stdout) {
            sys.puts(stdout);
        });
    });
     
    gulp.task('watch', function(){
        gulp.watch(sassdir + '/**/*.sass', ['css']);
        gulp.watch(coffeeDir + '/**/*.coffee', ['js']);
        gulp.watch('app/**/*.php', ['phpunit']);
    });
     
    // What tasks does running gulp trigger?
    gulp.task('default', ['css', 'js', 'phpunit', 'watch']);" | sudo tee /srv/www/$laravelProject/gulpfile.js

    # ---// Install more required apps \\---
    echo "Installing Gulp and Apps related."
    sleep 3
    sudo npm install gulp
    sudo npm install --save-dev gulp-util gulp-minify-css gulp-notify gulp-ruby-sass gulp-autoprefixer gulp-coffee gulp-ruby-sass gulp-rename gulp-livereload tiny-lr gulp-cache
    clear
}

# echo "YOU MUST RUN ==> $ composer update --dev <== WHEN FINISHED"
# echo "New addition to vendor packages is laracasts val;idation package"
# echo " $composer require laracasts/validation "
# echo "then add to providers in app/config/app.php"
# echo " 'Way\Generators\GeneratorsServiceProvider', "
# echo " 'Laracasts\Validation\ValidationServiceProvider' "
# echo "finally a composer dump autoload"
# echo " $ composer dump-autoload -o "

##---------------------
## Laravel Packages
##---------------------
##  within "require":
##  "laracasts/commander": "~1.0",
##
##
##  within "require-dev"
##      "way/generators":   "dev-master",
##      "fzaninotto/faker": "dev-master",
##  "codeception/codeception": "dev-master"
##  "laracast
##

##

afk_rollout()
{
    user_input
    update
    base_setup
    php_setup
    mysql_setup
    xdebug_setup
    phpmyadmin_setup
    git_setup
    composer_setup
    directories_setup
    laravel_setup
    restart_service apache2
    
}

exit_script()
{
    clear
    echo -e "\nScript terminated by user."
    exit 0
}

specific()
{
clear
echo -e "Please select from the following:\n"
echo '1) Base Setup'
echo '2) PHP setup'
echo '3) mySQL setup'
echo '4) xDebug Setup'
echo '5) GIT Setup'
echo '6) Composer Setup'
echo '7) Laravel Setup'
echo '8) Bower Setup'
echo '9) Gulp Setup'
echo '0) Exit'
read specific_option

if [[ $specific_option = "0" ]]; then
    exit_script
fi


echo "Update needed? n/y"
read need_update
if [[ $need_update = "y" ]]; then
    update
fi

case $specific_option in
    "1" ) base_setup;;
    "2" ) 
        echo "Provide current user name:"
        read currentUser
        php_setup;;
    "3" ) 
        echo "Provide mysql admin password:"
        read mysqlPasswd
        mysql_setup;;
    "4" ) xdebug_setup;;
    "5" ) 
        echo "Provide developers name:"
        read ownerName
        echo "Provide admin email:"
        read adminEmail
        git_setup;;
    "6" ) composer_setup;;
    "7" ) laravel_setup standalone;;
    "8" )
        echo "Provide laravelProject name:"
        read laravelProject 
        bower_setup;;
    "9" ) 
        echo "Provide laravelProject name:"
        read laravelProject 
        gulp_setup;;
    "0" ) exit_script;;
    * )
        echo -e "\n${red}Invalid selection.${NC}"
        specific;;
esac
specific
}

start() 
{
clear
echo -e "Please select from the following:\n"
echo '1) Rollout'
echo '2) Specific'
echo '3) Check Installed'
echo '0) Exit'
read option

case $option in
    1 ) afk_rollout;;
    2 ) 
        echo -e "\n"
        specific;;
    3 ) 
        echo "not implemented yet"
        start;;
    0 ) exit_script;;
    * )
        echo -e "\n${red}Invalid selection.${NC}"
        start;;
esac
clear
}

echo -e "\n" 
start
# afk_rollout

# echo "Script rollout complete."
