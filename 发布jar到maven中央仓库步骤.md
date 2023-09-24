# 发布jar到maven中央仓库步骤

maven仓库并不支持直接发布，需要第三方maven仓库发布，这里使用Sonatype ossrh.

## 1.注册JIRA账号
注册地址：https://issues.sonatype.org/secure/Signup!default.jspa


## 2.创建issue
创建链接：https://issues.sonatype.org/secure/CreateIssue.jspa?issuetype=21&pid=10134
<br>

- Issue Type选New Project
- Group Id可挂载公司域名，也可挂载github，如io.github.liusyy，提交后管理员会有评论让你在github建立一个空项目再按ta的操作就行

## 3. 安装并配置GPG
需要GPG签名的jar包才能推送,所以用GPG<br>
mac用GPG，windows用GPS4win<br>

生成GPG秘钥对
```
gpg --gen-key
```
上传公钥
```
gpg --keyserver hkp://keyserver.ubuntu.com:11371 --send-keys 公钥ID
```

附GPG常用命令
```
gpg --version 检查安装成功没
gpg --gen-key 生成密钥对
gpg --list-keys 查看公钥
gpg --keyserver hkp://keyserver.ubuntu.com:11371 --send-keys 公钥ID 将公钥发布到 PGP 密钥服务器
gpg --keyserver hkp://keyserver.ubuntu.com:11371 --recv-keys 公钥ID 查询公钥是否发布成功
```

## 4.配置maven的setting.xml
账号和密码是第1步申请的账号和密码
```
<servers>
        <server>
                <id>ossrh</id>
                <username></username>
                <password></password>
        </server>
</servers>
```

## 5.配置maven的pom.xml
必须包括name、description、url、licenses、developers、scm 等基本信息, snapshotRepository的id和第4步保持一致，参考例子
```
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>io.github.liubsyy</groupId>
    <artifactId>HotSecondsExtension</artifactId>
    <version>1.0.0</version>

    <name>HotSecondsExtension</name>
    <url>https://github.com/Liubsyy/HotSecondsExtension</url>
    <description>HotSecondsServer extension</description>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>8</maven.compiler.source>
        <maven.compiler.target>8</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <!-- 许可证信息 -->
    <licenses>
        <!-- GNU许可证 -->
        <license>
            <name>GNU General Public License v3.0</name>
            <url>https://github.com/Liubsyy/HotSecondsExtension/blob/master/LICENSE</url>
        </license>
    </licenses>
    <!-- SCM信息 -> 在github上托管 -->
    <scm>
        <connection>https://github.com/Liubsyy/HotSecondsExtension</connection>
        <developerConnection>https://github.com/Liubsyy/HotSecondsExtension.git</developerConnection>
        <url>https://github.com/Liubsyy/HotSecondsExtension</url>
    </scm>
    <!-- 开发者信息 -->
    <developers>
        <developer>
            <name>Liubsyy</name>
            <email>liubsyy@gmail.com</email>
            <url>https://github.com/Liubsyy</url>
            <roles>
                <role>Admin</role>
            </roles>
            <timezone>+8</timezone>
        </developer>
    </developers>


    <!-- 以下optional设置为true，这样引用方就不会间接依赖里面的包 -->
    <dependencies>

        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-context</artifactId>
            <version>4.3.2.RELEASE</version>
            <optional>true</optional>
        </dependency>

        <dependency>
            <groupId>com.baomidou</groupId>
            <artifactId>mybatis-plus</artifactId>
            <version>3.5.1</version>
            <optional>true</optional>
        </dependency>

        <dependency>
            <groupId>com.google.code.gson</groupId>
            <artifactId>gson</artifactId>
            <version>2.8.3</version>
        </dependency>



        <dependency>
            <groupId>org.hotswapagent</groupId>
            <artifactId>hotswap-agent</artifactId>
            <version>1.4.1</version>
            <optional>true</optional>

            <exclusions>
                <exclusion>
                    <artifactId>javassist</artifactId>
                    <groupId>org.javassist</groupId>
                </exclusion>
            </exclusions>
        </dependency>

    </dependencies>



    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.1</version>
                <configuration>
                    <source>1.8</source>
                    <target>1.8</target>
                    <encoding>UTF-8</encoding>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-resources-plugin</artifactId>
                <version>2.6</version>
                <executions>
                    <execution>
                        <id>process-META</id>
                        <phase>prepare-package</phase>
                        <goals>
                            <goal>copy-resources</goal>
                        </goals>
                        <configuration>
                            <outputDirectory>target/classes</outputDirectory>
                            <resources>
                                <resource>
                                    <directory>${basedir}/src/main/resources/</directory>
                                    <includes>
                                        <include>**/*</include>
                                    </includes>
                                </resource>
                            </resources>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>

        <testResources>
            <testResource>
                <directory>src/main/resources</directory>
            </testResource>
            <testResource>
                <directory>src/test/resources</directory>
            </testResource>
        </testResources>
    </build>

    <profiles>
        <profile>
            <id>default</id>
            <activation>
                <activeByDefault>true</activeByDefault>
            </activation>
            <build>
                <plugins>
                    <plugin>
                        <groupId>org.apache.maven.plugins</groupId>
                        <artifactId>maven-source-plugin</artifactId>
                        <version>2.2.1</version>
                        <executions>
                            <execution>
                                <phase>package</phase>
                                <goals>
                                    <goal>jar-no-fork</goal>
                                </goals>
                            </execution>
                        </executions>
                    </plugin>
                    <plugin>
                        <groupId>org.apache.maven.plugins</groupId>
                        <artifactId>maven-javadoc-plugin</artifactId>
                        <version>3.0.0</version>
                        <executions>
                            <execution>
                                <id>attach-javadocs</id>
                                <goals>
                                    <goal>jar</goal>
                                </goals>
                            </execution>
                        </executions>
                        <configuration>
                            <additionalOptions>
                                <additionalOption>-Xdoclint:none</additionalOption>
                            </additionalOptions>
                        </configuration>
                    </plugin>
                    <plugin>
                        <groupId>org.apache.maven.plugins</groupId>
                        <artifactId>maven-gpg-plugin</artifactId>
                        <version>1.6</version>
                        <executions>
                            <execution>
                                <phase>verify</phase>
                                <goals>
                                    <goal>sign</goal>
                                </goals>
                            </execution>
                        </executions>
                    </plugin>
                </plugins>
            </build>
            <distributionManagement>
                <snapshotRepository>
                    <!--            对应settings.xml内配置的<server>下的id -->
                    <id>ossrh</id>
                    <url>https://s01.oss.sonatype.org/content/repositories/snapshots</url>
                </snapshotRepository>
                <repository>
                    <id>ossrh</id>
                    <url>https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/</url>
                </repository>
            </distributionManagement>
        </profile>
    </profiles>



</project>
```

## 6. 发布jar包
用maven插件的的deploy发布，会让你输入GPG的密码，成功后在[https://s01.oss.sonatype.org/](https://s01.oss.sonatype.org/)用gira账号登录，在Staging Repository可以看到上传的jar

## 7.同步中央仓库
点击Close，如果检测没有问题再点Release，就可以同步到中央仓库了，半小时后[https://repo1.maven.org/maven2/](https://repo1.maven.org/maven2/)就能看到了，四个小时后[https://search.maven.org](https://search.maven.org)可搜到。

