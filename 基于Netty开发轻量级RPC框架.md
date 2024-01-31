
> 笔者在开发基于客户端/服务端模式通信的插件的时候，需要用到轻量级最小包依赖的RPC框架，而市面上的RPC框架份量过于庞大，最终打包下来都是几十兆甚至上百兆，而这里面大多数功能我都用不上，于是思来想去我决定写一款属于自己的轻量级RPC框架，简单易用快速接入。


## 关于技术选型
### 协议序列化/反序列化
网络通信基于TCP/IP为基础自定义应用层协议，常见的序列化/反序列化工具有java原生序列化，json,kryo,protobuf,fst,hessian等。

在不考虑跨语言的情况下，从序列化时长/序列化大小/易用性/扩展性这几方面考虑，综合性比较强的是kryo，但是kryo只支持java版本不能跨语言(据说能跨语言但是非常复杂，相当于不能跨语言了)，protobuf是性能最强的且支持跨语言，但是需要事先基于proto生成一个类，这会导致所有序列化和反序列化的时候只能用proto定义的类型。

最终选择kryo和protobuf两种序列化工具，使用的时候可选序列化类型，前者序列化几乎不受限制，后者支持跨语言，但是必须事先生成proto类型的类并使用其作为序列化工具。


### 通信框架使用
高性能异步非阻塞框架非Netty不可了，客户端和服务端基于Netty开发可事半功倍。

但是基于Netty再加上zk连接和各种工具打包完都需要20M左右，所以除了client和server端外，再开发一个client-mini模块，这个模块是client端基于nio开发的，性能虽然不如netty但是没有任何依赖，打包下来仅20kb。

### 服务注册和发现
注册中心选择zookeeper作为服务注册和服务发现，当然如果只用单点模式的话其实是不需要注册中心的，所以zookeeper是可选组件。


## 开发RPC框架

好了，有了上述这些技术就可以步入RPC框架的开发了，我这里分为了以下模块：
- base : 基础公共模块
- protocol : 协议层，包含应用层通信协议，以及序列化/反序列化，支持kryo和protobuf
- registry : 注册模块，基于zookeeper作为注册中心，包含注册服务和服务发现
- server : 服务端
- client : 客户端
- client-mini : 不依赖任何包的客户端，基于NIO

### 应用层协议
首先设计通信协议层，一个rpc框架通信的每一次请求主要包含服务名(serviceName)，函数名(methodName)，参数类型(paramTypes)和参数(params)等字段，当然再加上请求唯一id: traceId

```java
@ShadowEntity  
public class ShadowRPCRequest {  

    @ShadowField(1)  
    private String traceId;  

    @ShadowField(2)  
    private String serviceName;  

    @ShadowField(3)  
    private String methodName;  

    @ShadowField(4)  
    private Class<?>[] paramTypes;  

    @ShadowField(5)  
    private Object[] params;
}
```

上述ShadowRPCRequest是基于kryo序列化方式进行的一个定义，适合于客户端和服务端都是java，如果要跨语言，则需要使用protobuf，protobuf首先定义一个request.proto
```proto
syntax = "proto3";  
  
  
package com.liubs.shadowrpc.protocol.entity;  
option java_outer_classname="ShadowRPCRequestProto";  
  
message ShadowRPCRequest {  
    string traceId = 1;  
    string serviceName = 2;  
    string methodName = 3;  
    repeated string paramTypes = 4; //参数类名  
    repeated bytes params = 5; //bytes类型充当参数  
}
```

由于要跨语言，所以参数用bytes的集合类型，反序列化时需要二次解压缩成具体的类型，但是即便是这样仍然比kryo要快。

同理，与ShadowRPCRequest对应的消息体是响应ShadowRPCResponse
```java
@ShadowEntity  
public class ShadowRPCResponse {  
 
    @ShadowField(1)  
    private String traceId;  

    @ShadowField(2)  
    private int code;  

    @ShadowField(3)  
    private String errorMsg;  

    @ShadowField(4)  
    private Object result;
}
```


然后就是基于kryo和protobuf的序列化和反序列化了，kryo有很多种序列化策略，考虑到函数参数需要支持增减字段，所以kryo使用TaggedField策略，上面的@ShadowField注解是我进行的一些简单的封装，每次新增字段的时候需要加上注解即可，而protobuf天生就支持参数增减字段。


kryo的序列化和反序列化如下：
```java
public class KryoSerializer implements ISerializer {  
  
    private static ThreadLocal<Kryo> kryoThreadLocal = ThreadLocal.withInitial(() -> {  
        Kryo kryo = new Kryo();  

        kryo.setDefaultSerializer(new KryoFieldSerializerFactory());  

        kryo.setReferences(false);  
        kryo.setRegistrationRequired(false); //不需要提前注册  

        //注册一定会用到的，序列化可以省点空间  
        kryo.register(Class.class);  
        kryo.register(Class[].class);  
        kryo.register(Object[].class);  
        kryo.register(ShadowRPCRequest.class);  
        kryo.register(ShadowRPCResponse.class);  

        return kryo;  
    });  
  
  
  
    @Override  
    public byte[] serialize(Object object) {  

        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();  
        Output output = new Output(byteArrayOutputStream);  
        kryoThreadLocal.get().writeObject(output, object);  
        output.close();  
        return byteArrayOutputStream.toByteArray();  
    }  
  
    @Override  
    public <T> T deserialize(byte[] array, Class<T> clazz) {  

        ByteArrayInputStream byteArrayInputStream = new ByteArrayInputStream(array);  
        Input input = new Input(byteArrayInputStream);  
        T object = kryoThreadLocal.get().readObject(input, clazz);  
        input.close();  
        return object;  
    }  
}
```

protobuf的序列化和反序列化则是通过调用生成的proto类来实现序列化和反序列化的，

序列化：
```java
@Override  
public byte[] serialize(Object object) {  
    if (object instanceof MessageLite) {  
    return ((MessageLite) object).toByteArray();  
    }  
    if (object instanceof MessageLite.Builder) {  
    return (((MessageLite.Builder) object).build().toByteArray());  
    }  

    return new byte[0];  
}
```
反序列化:
```java

public <T> T deserialize(MessageLite messageLite,byte[] array, Class<T> clazz) {  
    return messageLite.getDefaultInstanceForType().getParserForType().parseFrom(array, 0, array.length);
}
```

### 消息的粘包/拆包和半包处理
TCP/IP是面向流的协议，操作系统底层其实并不关心我们自定义的应用层协议包是否完整，在高并发情况下，我们一次性发送多个包会被写入到一个流中，就是所谓的“粘包”，而接收方则需要根据收到的流进行拆分得到具体的包，称为“拆包”，


<img width="471" alt="QQ20240124-234312@2x" src="https://github.com/Liubsyy/SharedMarkdown/assets/132696548/7a089b0d-ea24-4ac2-b01d-6a897dae6d58">


比如上面的A,B,C,D,E,F是一次性发送的包，但是在发送D的时候超过了发送缓冲区被拆分成了D1和D2，而接收方从缓冲区读取到A,B,C,D1的时候完全不知所措，我们需要处理每个包的边界，并且还需要将第一次包中的D1和第二次包中的D2进行合并成D形成一个完整的包D。

业界最常用的方案是，发送方在写入缓冲区字节流的时候，先写入消息的长度，再写入消息字节，而接收方则先读取长度n，再读取n个字节，如果字节数不到n，则重制position，等下一次读取消息的时候再读取完整n个长度的字节流形成一个消息包。

写入字节流代码：
```java
int dataLength = data.length;  
out.writeInt(dataLength); // 先写入消息长度  
out.writeBytes(data); // 写入序列化后的数据
```

而接收方，用netty现成的LengthFieldBasedFrameDecoder即可
```java
pipeline.addLast(new LengthFieldBasedFrameDecoder(globalConfig.getMaxFrameLength(),  
0, 4, 0, 4));
```
这里的4表示4个字节(int类型)，它会先读取4个字节，再读取字节流，根据长度拆分不同的”Frame“，即我们需要的消息包。


### Netty构建通信框架
针对Netty构建通信网络初始化，最终目标是实现客户端发送一个ShadowRPCRequest消息就能调用服务并返回给客户端ShadowRPCResponse消息
```java
NioEventLoopGroup bossGroup = new NioEventLoopGroup();  
NioEventLoopGroup workerGroup = new NioEventLoopGroup();
ServerBootstrap bootstrap = new ServerBootstrap();  
bootstrap.group(bossGroup, workerGroup)  
.channel(NioServerSocketChannel.class)  
.childHandler(new ShadowChannelInitializer(serverConfig))  
.option(ChannelOption.SO_BACKLOG, 128)  
.childOption(ChannelOption.SO_KEEPALIVE, true);  
  
channelFuture = bootstrap.bind(port).sync();
```

childHandler里面使用ShadowChannelInitializer作为每个连接的处理
```java
public class ShadowChannelInitializer extends ChannelInitializer<SocketChannel> {  
  
    private ServerConfig serverConfig;  

    public ShadowChannelInitializer(ServerConfig serverConfig) {  
    this.serverConfig = serverConfig;  
    }  

    @Override  
    protected void initChannel(SocketChannel ch) throws Exception {  
    ChannelPipeline pipeline = ch.pipeline();  

    //qps请求量统计  
    if(serverConfig.isQpsStat()) {  
    pipeline.addLast(new QpsStatHandler());  
    }  

    //处理帧边界，解决拆包和粘包问题  
    pipeline.addLast(new LengthFieldBasedFrameDecoder(serverConfig.getMaxFrameLength(),  
    0, 4, 0, 4));  

    //消息序列化和反序列化  
    pipeline.addLast(new MessageHandler());  

    //服务处理  
    pipeline.addLast(new ServerHandler());  
    }  
}
```

紧接着就是对接收到客户端的ShadowRPCRequest消息的处理，ShadowRPCRequest里面包含了服务名，函数名以及参数，考虑到也有可能是protobuf类型ShadowRPCRequestProto，这里统一转换成抽象层的model: RequestModel，字段和ShadowRPCRequest都差不多，然后找到对应的服务触发逻辑和响应ServerHandler
```java
public class ServerHandler extends ChannelInboundHandlerAdapter {  
  
    @Override  
    public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {  

    // 打印验证影响速度，压测时去掉  
    //logger.info("Server received: " + msg);  

    IModelParser modelParser = serializeModule.getSerializer().getModelParser();  

    RequestModel requestModel = modelParser.fromRequest(msg);  

    executorService.execute(()->{  
    try {  

        ServiceLookUp serviceLookUp = new ServiceLookUp();  
        serviceLookUp.setServiceName(requestModel.getServiceName());  
        serviceLookUp.setMethodName(requestModel.getMethodName());  
        serviceLookUp.setParamTypes(requestModel.getParamTypes());  
        ServiceTarget targetRPC = serverModule.getRPC(serviceLookUp);  

        Object result = targetRPC.invoke(requestModel.getParams());  

        ResponseModel responseModel = new ResponseModel();  
        responseModel.setTraceId(requestModel.getTraceId());  
        responseModel.setCode(ResponseCode.SUCCESS.getCode());  
        responseModel.setResult(result);  

        // 响应客户端  
        ctx.writeAndFlush(modelParser.toResponse(responseModel));  
        } catch (Exception e) {  
        e.printStackTrace();  
    }  

    });  

    }  
  
}
```

至于根据RequestModel是如何找到对应的服务的，就需要在服务端启动的时候扫描所有的服务缓存到serverModule里面了，这样就能通过serverModule获取到targetRPC
```java
@ShadowModule  
public class ServerModule implements IModule {  
    private static final Logger logger = LoggerFactory.getLogger(ServerModule.class);  

    @ModuleInject  
    private SerializeModule serializeModule;  

    private ServerConfig serverConfig;  

    //所有服务  
    private Map<ServiceLookUp,ServiceTarget> allRPC = new ConcurrentHashMap<>();  

    public void init(ServerConfig serverConfig,List<String> packages) {  
        this.serverConfig = serverConfig;  
        //初始化服务  
        List<ShadowServiceHolder<ShadowService>> shadowServices = new ArrayList<>();  

        for(String packageName : packages) {  
        try {  
        shadowServices.addAll(AnnotationScanner.scanAnnotations(packageName, ShadowService.class));  
        } catch (IOException e) {  
        logger.error("scanService err",e);  
        }  
        }  

        for(ShadowServiceHolder<ShadowService> ShadowServiceHolder : shadowServices) {  
        ShadowService serviceAnnotation = ShadowServiceHolder.getAnnotation();  
        Class<?> serviceClass = ShadowServiceHolder.getClassz();  
        try {  
        Object o = serviceClass.newInstance();  


        for(Method method : serviceClass.getMethods()) {  

        if(Modifier.isStatic(method.getModifiers()) || !Modifier.isPublic(method.getModifiers())){  
        continue;  
        }  

        ServiceLookUp serviceLookUp = new ServiceLookUp();  
        serviceLookUp.setServiceName(serviceAnnotation.serviceName());  
        serviceLookUp.setMethodName(method.getName());  
        serviceLookUp.setParamTypes(method.getParameterTypes());  

        ServiceTarget serviceTarget = new ServiceTarget();  
        serviceTarget.setTargetObj(o);  
        serviceTarget.setMethod(method);  
        addRPCInterface(serviceLookUp,serviceTarget);  
        }  

        } catch (InstantiationException | IllegalAccessException e) {  
        throw new RuntimeException(e);  
        }  
        }  
    }  

    public void addRPCInterface(ServiceLookUp lookUp,ServiceTarget obj) {  
        allRPC.put(lookUp,obj);  
    }  

    public ServiceTarget getRPC(ServiceLookUp lookUp) {  
        return allRPC.get(lookUp);  
    }  
  
  
  
}
```

### 客户端调用远程rpc服务
刚才我们把服务端接收ShadowRPCRequest消息并触发逻辑返回ShadowRPCResponse消息实现了，而在客户端，我们只持有服务端的一个接口，要通过这个接口创建一个远程服务调用，来实现rpc调用，我们最终要实现的效果是这样的
```java
IHello helloService = shadowClient.createRemoteProxy(IHello.class,"shadowrpc://DefaultGroup/helloservice");  
  
System.out.println("发送 hello 消息");  
String helloResponse = helloService.hello("Tom");  
System.out.println("hello 服务端响应:"+helloResponse);
```

IHello是一个接口，没有任何实现类，实现类在服务端，而客户端我们通过创建一个远程代理的方式就能实现调用接口即发送ShadowRPCRequest消息到远程服务器。

我们这里使用动态代理，基于接口创建一个远程对象
```java
public static <T> T create(IConnection connection, Class<T> serviceStub, final String service) {  
  
    String[] serviceArr = service.replace("shadowrpc://","").split("/");  
    if(serviceArr.length < 2) {  
    throw new IllegalArgumentException("service参数不符合规范");  
    }  
    String group = serviceArr[0];  
    String serviceName = serviceArr[1];  

    return (T)Proxy.newProxyInstance(  
        serviceStub.getClassLoader(),  
        new Class<?>[]{serviceStub},  
        new RemoteHandler(connection,serviceStub,group,serviceName)  
    );  
}
```

RemoteHandler中实现代理对象的逻辑，发送消息到远程服务器
```java
public class RemoteHandler implements InvocationHandler {  
private static final Logger logger = LoggerFactory.getLogger(RemoteHandler.class);  
  
/**  
* 如果不使用注册中心，则必须有ShadowClient  
*/  
private IConnection clientConnection;  
  
/**  
* 远程接口stub  
*/  
private Class<?> serviceStub;  
  
  
/**  
* 集群  
*/  
private String group;  
  
/**  
* 服务名  
*/  
private String serviceName;  
  
  
private SerializeModule serializeModule = ModulePool.getModule(SerializeModule.class);  
  
public RemoteHandler(IConnection client, Class<?> serviceStub, String group,String serviceName) {  
    this.clientConnection = client;  
    this.serviceStub = serviceStub;  
    this.group = group;  
    this.serviceName = serviceName;  
}  
  
@Override  
public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {  
  
    try{  
        RequestModel requestModel = new RequestModel();  
        String traceId = UUID.randomUUID().toString();  
        requestModel.setTraceId(traceId);  
        requestModel.setServiceName(serviceName);  
        requestModel.setMethodName(method.getName());  
        requestModel.setParamTypes(method.getParameterTypes());  
        requestModel.setParams(args);  

        IModelParser modelParser = serializeModule.getSerializer().getModelParser();  
        Future<?> future = ReceiveHolder.getInstance().initFuture(traceId);  

        Channel channel = clientConnection.getChannel(group);  

        if(!channel.isOpen()) {  
        logger.error("服务器已关闭,发送消息抛弃...");  
        return null;  
        }  

        try{  
        channel.writeAndFlush(modelParser.toRequest(requestModel)).sync();  
        }catch (Exception e) {  
        logger.error("发送请求{}失败",traceId);  
        return null;  
        }  

        ResponseModel responseModel = (ResponseModel)future.get(3, TimeUnit.SECONDS);  
        if(responseModel != null) {  
        return responseModel.getResult();  
        }else {  
        ReceiveHolder.getInstance().deleteWait(traceId);  
        logger.error("超时请求,抛弃消息{}",traceId);  
        return null;  
        }  

    }catch (Throwable e) {  
    logger.error("invoke err",e);  
    }  

    return null;  
    }  
}
```


### 服务注册与发现
上面实现的客户端和服务端是单节点通信的，要实现服务注册与发现，需要注册中心Registry，服务端向注册中心注册服务，客户端订阅服务节点的变化，获取到服务节点列表后负载均衡rpc调用服务节点的机器。

<img width="398" alt="QQ20240124-222915@2x" src="https://github.com/Liubsyy/SharedMarkdown/assets/132696548/b1bd99a1-d42f-480a-8dc2-9278238eea01">


服务端在启动的时候注册服务到zookeeper
```java
serviceRegistry.registerServer(new ServerNode(group,IPUtil.getLocalIp(),port));

public void registerServer(ServerNode serverNode) {  
    try {  
    String path = ServiceRegistryPath.getServerNodePath(serverNode.getGroup(),  
    ServiceRegistryPath.uniqueKey(serverNode.getIp(),serverNode.getPort()));  
    this.zkNodePath = zooKeeperClient.create(path, serverNode.toBytes());  
    } catch (Exception e) {  
    e.printStackTrace();  
    }  
}
```
即在服务启动的时候创建节点 /shadowrpc/services/group/node1，这个node1的值就是ip+port，而在服务关闭的时候删除这个节点
```java
zooKeeperClient.delete(zkNodePath);
```


客户端就可以获取zk下/shadowrpc/services/group目录下的所有节点，监听目录变化，动态维护服务端的列表
```java
ServiceDiscovery serviceDiscovery = new ServiceDiscovery(ZK_URL);

//监听增量变化事件  
//初始化状态会同步SERVER_ADDED事件，所以不用获取全量  
serviceDiscovery.watchService(group, (changeType, serverNode) -> {  
    if(changeType == ServerChangeType.SERVER_ADDED) {  
        System.out.println("Child added: " + serverNode);  

        ShadowClient shadowClient = new ShadowClient(serverNode.getIp(),serverNode.getPort(),eventLoopGroup);  
        shadowClient.init();  
        finalShadowClients.add(shadowClient);  
    }else if(changeType == ServerChangeType.SERVER_REMOVED){  
        System.out.println("Child removed: " + serverNode);  

        Iterator<ShadowClient> iterator = finalShadowClients.iterator();  
        while(iterator.hasNext()) {  
            ShadowClient shadowClient1 = iterator.next();  
            if(serverNode.getIp().equals(shadowClient1.getRemoteIp()) && serverNode.getPort() == shadowClient1.getRemotePort()) {  
                shadowClient1.close();  
                iterator.remove();  
            }  
        }  
    }
});
```


然后维护这个List<ShadowClient>表示所有服务器列表的连接的增加和删除，最后负载均衡从这个List里面获取连接源发送消息到远程即可。
    
```java
    int nextBalance = pollingBalance.getNextBalance();  
    shadowClientGroup.getShadowClients(group).get(nextBalance).writeAndFlush(message).sync();
```    
    
### 精简版Client
刚才的Client和Server都是使用Netty作为异步非阻塞框架搭建的，有的时候对性能要求不高但是对最终的包大小有要求的时候(比如开发IDEA插件最好是kb级别的)，我们这里基于NIO来的Reactor模式来搭建一套简单版的rpc client。
    
我们还是参考上面的client，想服务端发送Request消息，下面是对NIO的一个简单封装NIOClient
```java
public void connect() throws IOException, ConnectTimeoutException {  
    socketChannel = SocketChannel.open();  
    socketChannel.configureBlocking(false);  
    selector = Selector.open();  
    socketChannel.register(selector, SelectionKey.OP_CONNECT);  

    socketChannel.connect(new InetSocketAddress(host, port));  
    isRunning = true;  

    //reactor模式  
    this.nioReactor = new NIOReactor(this);  
    nioReactor.start();  

    //等待连接完成  
    try{  
    waitConnection.get(nioConfig.getConnectTimeout(), TimeUnit.MILLISECONDS);  
    } catch (InterruptedException | ExecutionException | TimeoutException e) {  
    isRunning = false;  
    throw new ConnectTimeoutException(String.format("连接服务器%s:%d超时",host,port));  
    }  
}
    
public MessageSendFuture sendMessage(byte[] bytes) {  
    if(null == bytes || bytes.length == 0) {  
    return null;  
    }  

    ByteBuffer writeBuffer = ByteBuffer.allocate(4 + bytes.length); // 4 bytes for length field  
    writeBuffer.putInt(bytes.length); // Write length of the message  
    writeBuffer.put(bytes); // Write message itself  
    writeBuffer.flip();  

    // Add to write queue  
    MessageSendFuture future = new MessageSendFuture(writeBuffer);  
    writeQueue.add(future);  

    // Change interest to OP_WRITE  
    SelectionKey key = socketChannel.keyFor(selector);  
    if(!key.isValid()) {  
    return null;  
    }  
    key.interestOps(SelectionKey.OP_WRITE);  
    selector.wakeup();  

    return future;  
}
```
这里写入消息sendMessage的时候，也是先写入长度4字节bytes.length，再写入bytes。    
    
    
下面是基于Reactor模式实现对连接消息，读写消息的统一处理
```java
while (nioClient.isRunning()) {  
    try {  
    if (selector.select() > 0) {  
    processSelectedKeys();  
    }  
    } catch (IOException e) {  
    logger.error("selector err",e);  
    }  
}
    
private void processSelectedKeys() throws IOException {  
    Set<SelectionKey> selectedKeys = selector.selectedKeys();  
    Iterator<SelectionKey> iter = selectedKeys.iterator();  

    while (nioClient.isRunning() && iter.hasNext()) {  
    SelectionKey key = iter.next();  

    if (key.isConnectable()) {  
    handleConnect(key);  
    }  
    if (key.isWritable()) {  
    handleWrite(key);  
    }  
    if (key.isReadable()) {  
    handleRead(key);  
    }  
    iter.remove();  
    }  
}  
```
    
而对读消息的拆包和半包处理原理也是和上面一样的，也是读取长度4字节，再读取对应长度的字节，如果不够重置ByteBuffer的position用于下次读取,这里是一个精简版本
```java
private void handleRead(SelectionKey key) {  
  
    ByteBuffer buffer = readByteBuffer;  

    int numRead = 0;  
    try {  
        numRead = socketChannel.read(buffer);  
    } catch (IOException e) {  
        handleClose(key);  
        return;  
    }  

    if (numRead > 0) {  
        buffer.flip(); // 切换到读模式  
        // 处理缓冲区中的所有数据  
        while (buffer.remaining() > 4) { // 确保有足够的数据读取长度字段  
            buffer.mark();  
            int length = buffer.getInt();  
            //System.out.printf("read length=%d,remain=%d\n",length,buffer.remaining());  

            if (length <= buffer.remaining()) {  
            byte[] data = new byte[length];  
                buffer.get(data);  
                nioClient.getReceiveMessageCallBack().handleMessage(data);  
            } else {  
                // 数据长度不足以构成一个完整的消息，重置并退出循环  
                buffer.reset();  
                break;  
            }  
        }  

        if (buffer.hasRemaining()) {  
            buffer.compact(); // 移动未处理数据到缓冲区开始位置  
        } else {  
            buffer.clear(); // 如果没有剩余数据，清空缓冲区  
        }  

        lastActiveTime = System.currentTimeMillis();  

    } else if (numRead < 0) {  
        //接收到-1表示服务器关闭  
        handleClose(key);  
    }  
}
```
   
## RPC框架的使用

经过上述酣畅淋漓的rpc框架搭建，基本五脏俱全的rpc框架ShadowRPC就搭建完成了，下面是一些服务例子。
    
### 定义实体类
```java
@ShadowEntity
public class MyMessage {
    @ShadowField(1)
    private String content;

    @ShadowField(2)
    private int num;
}
```
如果是protobuf方式，可定义描述文件    
```proto
message MyMessage {
    string content = 1;
    int32 num = 2;
}
```    
然后直接用maven插件protobuf-maven-plugin生成实体
    
### 编写接口和服务类
```java
@ShadowInterface
public interface IHello {
    String hello(String msg);
    MyMessage say(MyMessage message);
}
```
protobuf方式的接口需要保证参数和返回类型都是protobuf定义的类型
```java
@ShadowInterface
public interface IHelloProto {
    MyMessageProto.MyMessage say(MyMessageProto.MyMessage message);
}
```

然后编写服务实现类
    
```java
@ShadowService(serviceName = "helloservice")
public class HelloService implements IHello {
    @Override
    public String hello(String msg) {
        return "Hello,"+msg;
    }
    @Override
    public MyMessage say(MyMessage message) {
        MyMessage message1 = new MyMessage();
        message1.setContent("hello received "+"("+message.getContent()+")");
        message1.setNum(message.getNum()+1);
        return message1;
    }
}
```    
### 指定序列化类型和端口，启动服务端
单点启动模式如下:
``` java
ServerConfig serverConfig = new ServerConfig();
        serverConfig.setQpsStat(true); //统计qps
        serverConfig.setPort(2023);

ServerBuilder.newBuilder()
        .serverConfig(serverConfig)
        .addPackage("rpctest.hello")
        .build()
        .start(); 
```
    
使用zk作为集群模式启动
```java
String ZK_URL = "localhost:2181";
ServerConfig serverConfig = new ServerConfig();
serverConfig.setGroup("DefaultGroup");
serverConfig.setPort(2023);
serverConfig.setRegistryUrl(ZK_URL);
serverConfig.setQpsStat(true); //统计qps
serverConfig.setSerializer(SerializerEnum.KRYO.name());
ServerBuilder.newBuilder()
                .serverConfig(serverConfig)
                .addPackage("rpctest.hello")
                .build()
                .start();
```    

### 客户端调用rpc服务
 ```java   
ModulePool.getModule(ClientModule.class).init(new ClientConfig());

ShadowClient shadowClient = new ShadowClient("127.0.0.1",2023);
shadowClient.init();

IHello helloService = shadowClient.createRemoteProxy(IHello.class,"shadowrpc://DefaultGroup/helloservice");

logger.info("发送 hello 消息");
String helloResponse = helloService.hello("Tom");
logger.info("hello 服务端响应:"+helloResponse);

MyMessage message = new MyMessage();
message.setNum(100);
message.setContent("Hello, Server!");

System.out.printf("发送请求 : %s\n",message);
MyMessage response = helloService.say(message);
System.out.printf("接收服务端消息 : %s\n",response);    
```
    
使用zk作为服务发现负载均衡调用各个服务器
```java
ClientConfig config = new ClientConfig();
config.setSerializer(SerializerStrategy.KRYO.name());
ModulePool.getModule(ClientModule.class).init(config);
String ZK_URL="localhost:2181";
ShadowClientGroup shadowClientGroup = new ShadowClientGroup(ZK_URL);
shadowClientGroup.init();

IHello helloService = shadowClientGroup.createRemoteProxy(IHello.class, "shadowrpc://DefaultGroup/helloservice");
List<ShadowClient> shadowClientList = shadowClientGroup.getShadowClients("DefaultGroup");

System.out.println("所有服务器: "+shadowClientList.stream().map(c-> c.getRemoteIp()+":"+c.getRemotePort()).collect(Collectors.toList()));

for(int i = 0 ;i<shadowClientList.size() * 5; i++) {
    String hello = helloService.hello(i + "");
    System.out.println(hello);
}
```    

## 性能测试
目前Mac笔记本16G 4核测试的rpc调用hello逻辑，如果使用kryo序列化/反序列化，100w个请求耗时27秒，平均QPS为3.7w，如果使用protobuf序列化/反序列化耗时25秒, 平均QPS为4w，如果用M1芯片的Mac，平均QPS可以达到7W+，最高QPS可以达到10w+。                           
## 源码
                                         
篇幅有限，介绍的时候不够完整有些遗漏，所有源码见:
[https://github.com/Liubsyy/ShadowRPC](https://github.com/Liubsyy/ShadowRPC)                              
目前仅供学习交流使用，后续我将逐步打磨此rpc框架达到企业级水准。                              
                                         
> 本RPC框架使用的方案和技术栈都是业界通用，项目中部分源码如有雷同纯属巧合。                                        
