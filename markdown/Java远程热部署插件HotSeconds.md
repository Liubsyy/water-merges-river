
## 前言
我们在开发调试的过程中，经常在打包和重启服务器中消耗大量的时间，这将浪费我们大量的青春，这里介绍一款本人开发的Java远程热部署插件HotSeconds，包括HotSecondsServer和HotSecondsClient，相对传统部署来说，效率可以提升百倍。

## 功能介绍

### 1.热部署代码
包括修改代码，新增字段，新增方法，新增类，打破了原生JDK中Instrument机制只能修改方法体的不足。同时还支持一些常用框架的热更新，比如Spring新增一个Autowired字段或者SpringMVC新增一个Controller方法，也是支持热更新的。

下面演示一个新增SpringMVC字段和方法的热部署

![](https://github.com/Liubsyy/HotSecondsIDEA/blob/master/img/gif/springmvc1.gif)


### 2.热部署资源文件
下面演示一个热部署MyBatis的xml文件，也是右键直接热部署生效
![](https://github.com/Liubsyy/HotSecondsIDEA/blob/master/img/gif/mybatis1.gif)


### 3.批量热更新修改的文件
修改了多个文件的情况下，直接打开热部署面板，可将修改过的文件热部署到服务器，支持按文件修改时间戳热部署，也可以将版本控制下(Git/SVN等)未提交的文件热部署
![](https://github.com/Liubsyy/HotSecondsIDEA/blob/master/img/gif/batchhot.gif)


### 4.执行远程函数
无需调用远程Http或者RPC接口，就能直接触发需要的函数，这对于调试来说可是非常方便的，当然也包括在沙箱环境修复脏数据。<br>
直接在函数上右键选择远程执行函数，即可触发具体的函数逻辑，这里分为四种情况，静态，非静态，有参数，无参数。<br>
无参数可以直接触发，如果是非静态字段，会弹出当前类的所有对象的选择框，选择后触发。<br>
有参数的情况，会弹出对象选择框和参数输入框，输入选择后触发逻辑。<br>
目前参数只支持byte,short,boolean,char,int,double,float,long,Bigdecimal。<br>
复杂参数的函数，可以写一个静态无参的函数，触发需要的函数，然后远程热部署整个新写的静态无参的函数的类即可。<br>


### 5.远程查看字段值
包括静态字段和非静态字段，直接在字段上右键，就能查看该字段的值。
非静态字段是先弹出显示当前类的所有对象实例的框，选择具体的对象后即可获取该对象的字段值。

## 安装教程
详见[https://github.com/Liubsyy/HotSecondsIDEA](https://github.com/Liubsyy/HotSecondsIDEA)





