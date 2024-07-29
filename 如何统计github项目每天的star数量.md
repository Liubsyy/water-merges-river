

## 背景

我们写的github开源项目可以看到star数量和通知，但是没有统计每天的star的数据，有时我们想看看某天一共有多少个star，于是我写了个脚本统计每天的star数量。

## 实现

github项目的每个star的时间可以通过github的API https://api.github.com/repos/${author}/${repository}/stargazers 获取每个star的时间，下面是一个简单的例子：

```shell
curl -s -H "Accept: application/vnd.github.v3.star+json" \
        "https://api.github.com/repos/Liubsyy/FindInstancesOfClass/stargazers?per_page=3&page=1"
```


可获得以下结果：
```
[
  {
    "starred_at": "2023-10-25T01:51:45Z",
    "user": {
      ...
    }
  },
  {
    "starred_at": "2023-12-03T09:04:53Z",
    "user": {
      ...
    }
  },
  {
    "starred_at": "2023-12-18T06:52:31Z",
    "user": {
      ...
    }
  }
]
```

其中**starred_at**就是star的UTC时间，这个时间再加上8个小时的时区差，就是北京时间，然后按天进行统计即可。

<br>

以下是具体的脚本：

```shell
#!/bin/bash

#repository
stat_repository="Liubsyy/FindInstancesOfClass"
token=""
#token="ghp_QGosy2asdasdasdasdasdasdasdasda"

function fetch_stargazers {
    local page=1
    local per_page=100
    local data

    while true
    do
        data=$(curl -s -H "Accept: application/vnd.github.v3.star+json" \
        -H "Authorization: $token" \
        "https://api.github.com/repos/$stat_repository/stargazers?per_page=$per_page&page=$page")

        if [ ${#data} -lt 10 ]; then
            break
        fi

        starred_at=$(echo "$data" | grep -o '"starred_at": "[^"]*"' | awk -F'"' '{print $4}')

        # UTF +8h
        for timestamp in $starred_at
        do
            #linux
            #new_time=$(date -u -d "$timestamp 8 hours" +"%Y-%m-%d")

            #mac
            new_time=$(date -v +8H -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%Y-%m-%d")

            echo "$new_time"
        done
        ((page++))
    done
}

try_data=$(curl -s -H "Accept: application/vnd.github.v3.star+json" \
        -H "Authorization: $token" \
        "https://api.github.com/repos/$stat_repository/stargazers?per_page=1&page=1")
if echo "$try_data" | grep -q "API rate limit"; then
    echo "$try_data"
    exit 1
fi
echo "date   stars"
fetch_stargazers | sort | uniq -c | awk '{print $2 , $1}'
```

<br>
执行脚本可得到每天统计的结果：

```
date   stars
2023-10-25 1
2023-12-03 1
2023-12-18 1
2023-12-22 1
2024-01-02 1
2024-01-09 1
2024-01-16 3
2024-01-17 2
2024-01-31 1
2024-02-18 1
2024-05-07 1
2024-05-11 2
2024-05-17 1
2024-05-21 1
2024-06-12 1
2024-07-08 1
2024-07-09 1
2024-07-12 1
2024-07-26 1
```

这个API访问频率有限制，最好是带上token进行访问统计，另外linux和mac的date命令有差异，linux系统new_time这里可去掉注释用linux的命令。

本脚本只提供一种思路，根据本思路用任何编程语言和脚本都可以实现star数量的统计。


