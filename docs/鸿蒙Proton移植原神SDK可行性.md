# **Proton移植至鸿蒙（HarmonyOS NEXT）可行性评估报告与SDK产品需求文档**

## **1\. 可行性评估报告**

### **1.1 鸿蒙系统架构与系统调用翻译可行性**

鸿蒙NEXT（HarmonyOS NEXT）舍弃了传统的安卓开源项目（AOSP）代码，全面切换至自研的洪蒙微内核架构 1。从用户态来看，鸿蒙NEXT的运行环境与Linux具有极高的相似性，其标准C库（libc）基于musl libc进行深度定制与派生，并通过“ABI兼容适配层”（ABI-compliant shim）对Linux标准的系统调用进行封装和映射 1。这为运行于Linux ARM64架构下的兼容性中间件（如Box64、Wine及Proton核心组件）在鸿蒙系统中的本地化编译奠定了技术基础 1。  
在系统底层，鸿蒙NEXT采用了只读压缩文件系统 EROFS 和分布式文件系统 HMDFS，日志输出则依托 hilog 框架，而传统的系统属性控制则被替代为鸿蒙特有的“参数”（Parameters）管理机制 1。这些特性的变更为Proton移植时的底层文件路径映射、标准输出/错误流重定向以及环境变量模拟引入了新的适配需求 1。  
通过原生开发套件（NDK），技术团队可以引入C/C++模块，这些模块将编译为标准的ELF共享对象（Dynamic Shared Objects, .so） 1。这意味着Proton核心的二进制翻译器与API转换层能够以原生动态链接库的形式在鸿蒙应用沙盒中加载和执行 4。

### **1.2 外部二进制文件加载限制与用户态映像载入**

鸿蒙NEXT的安全架构实施了极严格的代码签名与动态加载限制 1。系统严禁应用在运行时使用标准系统函数 dlopen() 加载未随应用一同打包签名、或者从外部动态下载的二级动态链接库 6。所有在运行时执行的二进制代码必须在编译打包阶段封包于鸿蒙功能包（HAP）或鸿蒙共享包（HSP）中，并通过专用的 hap-sign-tool.jar 进行基于华为根证书链的 V3 签名验证 1。若将外部下载的 .so 写入沙盒路径并尝试加载，系统将直接拦截并报错 6。  
针对此项硬性限制，运行Windows x86\_64架构的《原神》国服游戏程序（即 YuanShen.exe 以及伴随的 .dll 动态链接库）面临无法直接由鸿蒙系统动态载入的困境 9。为了在不违反鸿蒙底层安全策略的前提下实现“直接游玩”，移植方案必须采用“用户态自解析映射”的设计。  
在这种设计下，Windows PE（Portable Executable）格式的游戏二进制文件不作为鸿蒙系统的“可执行代码”载入，而是作为只读的“非执行数据资源”（Asset）放入应用的资源目录 1。SDK内部需集成一套定制的用户态PE加载器 9。该加载器在应用启动时读取未签名的PE文件数据，在用户态虚拟内存空间中通过匿名内存映射（Anonymous mmap）开辟内存块，手动解析COFF/PE头部，重定位节区（Sections），并根据PE导入地址表（IAT）将Windows系统API的符号引用手动绑定至SDK内部预先编译并获得合规签名的ARM64鸿蒙原生动态链接库中 9。通过这种方式，未签名的外部游戏二进制代码被限制在用户态翻译器控制的虚拟地址空间内执行，从而规避了鸿蒙系统对未签名ELF动态链接库的底层加载拦截 6。

### **1.3 写或执行（W^X）内存保护机制与JIT编译权限的设备兼容性边界**

在处理器指令集转换层面，将Windows平台的x86\_64指令集转换为鸿蒙设备原生的ARM64指令集，必须依赖动态重编译器（DynaRec/JIT）以确保运行效率 3。相比纯解释执行，JIT编译能够提供 ![][image1] 的运行速度提升 3。然而，JIT编译机制的本质是动态分配可写内存，写入翻译后的ARM64机器码，随后将其修改为可执行属性并跳转执行 13。这一过程直接冲突于鸿蒙系统默认实施的强制 ![][image2]（写或执行不可同时出现）物理页表级内存保护 1。  
鸿蒙NEXT对JIT动态代码生成权限设置了极高壁垒 14。该权限（对应系统内部受限权限集）不向标准的第三方消费级手机应用开放 14。根据鸿蒙系统规格：

* 该权限仅适用于平板（Tablets）、个人电脑（PCs）以及2合1（2-in-1）设备上的应用 14。  
* 申请该权限的应用必须是经过企业技术支持渠道审批并进入白名单（Allowlist）的企业特许应用 14。  
* 应用必须适应安全盾（Secure Shield）模式，确保在该特许模式下运行不发生系统崩溃 14。

若在不具备JIT编译权限的设备（如普通鸿蒙NEXT手机）上强行运行移植SDK，翻译引擎将被迫回退至纯解释执行（Interpreter）模式 3。由于《原神》作为大型3D开放世界游戏对CPU指令吞吐量有着极高的要求，解释执行带来的高昂开销将导致帧率无法达到可玩水平，甚至引发系统看门狗（Watchdog）因超时而强行杀进程 7。因此，使用该移植SDK的游戏在实际分发和体验中，**只能兼容个人电脑、平板及2合1形态的鸿蒙设备**，无法在标准的手机移动端实现流畅游玩 14。

### **1.4 国服原神反作弊（ACE）的兼容性瓶颈与破解方案**

《原神》国服版本集成了极其严格的反作弊系统（包含 Anti-Cheat Expert, 简称 ACE，以及内核级保护驱动 mhyprot2.sys 等组件） 15。在传统的Windows环境中，反作弊系统需要向操作系统注册并加载内核模式驱动，用以监控物理内存、硬件中断及敏感系统调用，防止内存劫持与注入 9。  
然而，在鸿蒙微内核架构下，Windows内核驱动（.sys）既无法通过动态链接载入，也无法被微内核解释运行 1。同时，Proton作为用户态翻译容器，并没有提供真实内核级别的特权，其运行权限完全受限于当前的鸿蒙应用用户空间限制 15。  
分析Linux平台运行《原神》的历史演进可以发现，其反作弊系统在特定的Linux/Wine环境下实现了对Steam Deck硬件的定向识别与豁免 16。ACE反作弊系统内部的用户态基础模块（ACE-Base.dll 等）会检测系统的EDID数据、特定的系统环境变量以及硬件标识 16。当确认运行环境为合规的Steam Deck设备时，反作弊系统会转为用户态温和监控模式，不强行阻断非内核态加载，从而允许游戏继续执行 16。  
要确保国服《原神》通过鸿蒙SDK“直接游玩”且不被封号，SDK必须在用户态针对ACE和国服反作弊机制构建高度定制化的“反作弊兼容层”，其核心攻坚策略包含以下三项：

\+---------------------------------------------------------------------------------+  
|                       反作弊兼容层（Anti-Cheat Shim）工作流                     |  
\+---------------------------------------------------------------------------------+  
|                                                                                 |  
|                                                   |  
|         │                                                                       |  
|         ├── 1\. 发起加载 mhyprot2.sys 驱动请求                                   |  
|         │      ▼                                                                |  
|         │   ──\> 仿真返回 NT\_SUCCESS (驱动加载成功)       |  
|         │                                                                       |  
|         └── 2\. 用户态反作弊模块 (ACE-Base.dll) 调用 API 查询运行环境             |  
|                ▼                                                                |  
|                                                                |  
|                ├── 拦截 EDID/硬件接口查询 ──\> 返回 Steam Deck 模拟参数    |  
|                └── 设置环境变量注入 ──\> 注入 STEAM\_DECK=1 \[17\]               |  
|                                                                                 |  
\+---------------------------------------------------------------------------------+

通过这一重构的仿真适配层，游戏客户端在初始化反作弊验证时，其内核驱动加载请求均被重定向至SDK的安全桩中，同时用户态安全审计代码能够获得预期的系统环境响应，从而确保国服《原神》能够平稳通过初始启动安全检查并直接进入游戏大厅 16。

### **1.5 图形翻译与渲染管线适配**

国服《原神》PC端采用 Direct3D 11 与 Direct3D 12 作为主渲染引擎 11。鸿蒙NEXT底层提供了对Vulkan标准API的原生支持（最高支持Vulkan 1.4规格，通过鸿蒙NDK的 libs/arm64 路径暴露） 4。因此，移植工作的图形部分需要将 D3D 调用高效率地转换为 Vulkan 指令流 11。  
DXVK组件负责将 D3D11 调用转换为 Vulkan，而 vkd3d-proton 组件则负责将复杂的 D3D12 管线（包括资源屏障、描述符堆、动态管线状态对象等）映射至 Vulkan 1.3/1.4 系统 11。这两项组件必须在鸿蒙NDK环境中，使用支持 libc++\_shared.so 命名空间的 MinGW-GCC 交叉编译工具链重新编译为原生 .so 动态库，并绑定到前述的用户态PE加载器中 5。在实际运行中，图形翻译层必须支持动态着色器编译与SPIR-V高速缓存机制，以规避在鸿蒙微内核设备上进行实时顶点/像素着色器翻译带来的偶发性掉帧与画面卡顿 2。

## **2\. SDK 产品需求文档（PRD）**

### **2.1 产品定义与交付形态**

**Teyvat-Bridge SDK（泰瓦特兼容桥接SDK）** 是一套面向鸿蒙NEXT（PC、平板及2合1端）的游戏兼容性中间件 8。该SDK通过鸿蒙共享包（Harmony Shared Package, 简称 HSP）的形式进行封装和分发 8。  
HSP 作为一种动态共享包，不与特定的应用包名耦合，其包名在最终整包构建时由鸿蒙编译链工具自动替换为宿主应用的 Bundle Name 8。这使得游戏开发者能够直接将SDK集成到鸿蒙应用工程中，将原生的Windows版游戏二进制镜像作为无执行属性的 Asset 资源进行配包打包，从而实现免重构、零代码改造的鸿蒙本地化部署 1。

\+---------------------------------------------------------------------------------+  
|                       Teyvat-Bridge SDK (HSP) 逻辑分层架构                      |  
\+---------------------------------------------------------------------------------+  
|                                                                                 |  
|   ┌─────────────────────────────────────────────────────────┐                   |  
|   │               宿主鸿蒙应用 (HarmonyOS App)               │                   |  
|   │      (打包 Windows 国服原神 PE 数据集作为只读 Asset 资源)     │                   |  
|   └────────────────────────────┬────────────────────────────┘                   |  
|                                │ 1\. 引导初始化                                  |  
|                                ▼                                                |  
|   ┌─────────────────────────────────────────────────────────┐                   |  
|   │               Teyvat-Bridge SDK (HSP)                   │                   |  
|   │                                                         │                   |  
|   │ ┌────────────────────────┐  ┌─────────────────────────┐ │                   |  
|   │ │     用户态 PE 加载器    │  │   ARM64 动态翻译器引擎  │ │                   |  
|   │ │    (无符号 dlopen 绕过) │  │  (双重映射 JIT / 解释器) │ │                   |  
|   │ └───────────┬────────────┘  └────────────┬────────────┘ │                   |  
|   │             │ 2\. 映射重定位              │ 3\. 翻译执行  │                   |  
|   │             ▼                            ▼              │                   |  
|   │ ┌─────────────────────────────────────────────────────┐ │                   |  
|   │ │                 Wine-Win32 系统调用模拟器            │ │                   |  
|   │ │        (PE 模块隔离与 libc-musl 系统桥接适配层)       │ │                   |  
|   │ └───────────────────────────┬─────────────────────────┘ │                   |  
|   │                             │ 4\. 渲染管线提交           │                   |  
|   │                             ▼                           │                   |  
|   │ ┌─────────────────────────────────────────────────────┐ │                   |  
|   │ │                  DXVK / vkd3d-proton                │ │                   |  
|   │ │              (D3D11 / D3D12 至 Vulkan 1.4 转换)     │ │                   |  
|   │ └───────────────────────────┬─────────────────────────┘ │                   |  
|   └─────────────────────────────┼───────────────────────────┘                   |  
|                                 │ 5\. 原生接口调用                               |  
|                                 ▼                                                |  
|   ┌─────────────────────────────────────────────────────────┐                   |  
|   │                   鸿蒙系统（HarmonyOS NEXT）             │                   |  
|   │       (HongMeng 物理内核 / Native NDK Ns / GPU 驱动)     │                   |  
|   └─────────────────────────────────────────────────────────┘                   |  
|                                                                                 |  
\+---------------------------------------------------------------------------------+

### **2.2 核心功能性需求**

SDK的核心功能在于无缝加载、高效运行以及稳定绕过反作弊策略。具体核心功能需求如下表所示：

| 需求标识 | 需求维度 | 需求细则说明 | 优先级 | 验收/验证标准 |
| :---- | :---- | :---- | :---- | :---- |
| **FR-01** | 用户态 PE 映像载入 | SDK 必须包含独立于宿主 OS 动态链接器的 PE 解析与重定位引擎，从 HAP rawfile 目录读取 Windows 目标 PE，通过匿名物理内存段模拟映像空间 1。 | **P0** | 无需系统级 dlopen 系统调用，成功在虚拟地址空间中还原 PE 映像结构，生成有效的内部基址 6。 |
| **FR-02** | 符号重绑定与 IAT 修正 | 自动扫描 PE 的导入地址表，拦截定位到 Windows 核心 API（如 kernel32.dll）的符号，并替换绑定为 SDK 自身搭载的 Wine 宿主桩函数地址 9。 | **P0** | 模拟器的符号查询和重定位无死锁发生，外部游戏 DLL 无法触发鸿蒙未签名 ELF 加载崩溃 1。 |
| **FR-03** | 动态重编译（DynaRec） | 在具备特许 JIT 编译权限的鸿蒙 2合1/PC 硬件上激活 JIT 指令编译转换，建立动态代码高速缓存 3。 | **P0** | 在 CPU 运算场景下，指令翻译产生的开销不高于原生机器码开销的 ![][image3] 19。 |
| **FR-04** | 图形渲染指令翻译 | 拦截游戏的 Direct3D 11/12 调用流，通过集成重新编译的 DXVK 和 vkd3d 库将渲染指令重写为 Vulkan 1.4 标准格式，并呈现至鸿蒙本地 NativeWindow 4。 | **P0** | 游戏渲染画面能成功输出到宿主 Activity/Ability 的 UI 组件，画面中模型材质、阴影渲染与 PC 原生无异，无闪烁 1。 |
| **FR-05** | 反作弊环境欺骗与注入 | 拦截游戏初始化时对 Windows 驱动服务加载（如 mhyprot2.sys）的请求，对该句柄创建以及驱动加载动作进行截断，恒定返回模拟成功状态码 9。 | **P0** | 游戏客户端初始化阶段能跳过内核级驱动真实挂载步骤，成功拉起用户态 ACE 客户端进程，且无“检测到安全威胁”闪退 15。 |
| **FR-06** | 虚拟环境硬件伪装 | 针对 ACE-Base.dll 发起的 EDID、SMBIOS、系统注册表等底层硬件参数查询，重定向至伪装层，注入 Steam Deck 豁免特征参数 16。 | **P1** | 游戏进入登录大厅，成功通过 ACE 云端安全握手校验，运行时间 ![][image4] 未被服务器中断或作弊封禁 16。 |
| **FR-07** | 输入系统与多模设备映射 | 适配鸿蒙 NDK 设备输入接口（键盘、鼠标及原生游戏手柄），将捕获的原生 POSIX 输入事件包装并注入到 Windows 消息循环队列中 4。 | **P1** | 支持键盘 WASD 移动、鼠标视角平滑旋转、手柄震动响应，延迟 ![][image5]。 |

### **2.3 非功能性需求**

#### **性能与帧率控制（Performance & Frame Pacing）**

* **流畅度指标**：在符合硬件准入标准的鸿蒙 2合1/PC 设备（基于麒麟/磐石高性能架构及独立GPU）上，中等画质、1080P分辨率下，游戏运行帧率必须稳定维持在 ![][image6]，允许的帧抖动率控制在 ![][image7] 以内。  
* **延迟与计算开销控制**：单帧 CPU 指令翻译加上 API 翻译的综合耗时必须控制在 ![][image8] 以内。单帧总体物理渲染链路公式必须满足：  
  ![][image9]

#### **冷启动与初始化时延（Cold Start & Initialization）**

* **启动规范**：必须严格契合华为应用市场对旗舰级高规格应用的审核标准 7。游戏应用冷启动（即用户点击图标至首帧主界面渲染加载完成）的综合时延必须限制在 ![][image10] 7。  
* **初始化分步时延**：  
  * SDK 基础运行环境、动态链接库和命名空间隔离建立时延 ![][image11] 5。  
  * Windows PE 加载、重定位、符号导入及 IAT 绑定总耗时 ![][image12] 9。  
  * 反作弊用户态欺骗代理以及 DXVK 渲染器管道预初始化时延 ![][image13] 11。

#### **运行期物理内存及高速缓存分配策略（Memory & Cache Allocations）**

* **物理内存管理**：SDK 进程空间占用的额外运行时内存（包含指令重编译高速缓存、JIT 块缓冲区、Vulkan 转换对象等）必须控制在 ![][image14]。  
* **高速缓存优化**：为防止在 8GB/16GB 运存设备上产生内存抖动与内存溢出（OOM），必须默认开启 Dynamic L1 查找高速缓存并禁用开销高昂的 L2 高速缓存 21。指令翻译缓冲区（Translation Buffer）的分配策略需适配操作系统的透明大页（Transparent Huge Pages, THP），通过显式申请非 THP/THP 缓冲，将指令转换高速缓存引发的 iTLB 未命中次数减半，有效平抑 L2 TLB 查找压力 21。

\+---------------------------------------------------------------------------------+  
|                         SDK 运行期物理内存开销与缓存分配                        |  
\+---------------------------------------------------------------------------------+  
|  物理运存 (RAM) 总分配上限: 512 MB                                                |  
|                                                                                 |  
|  (默认启用，降低内存压力)          |  
|  (申请非-THP缓冲)               |  
|  (Vulkan管线编译)                |  
|                   |  
|                                                                                 |  
|  \* L2 Cache Lookup Table: 默认禁用 (可节省约 200MB \- 300MB 冗余内存开销)     |  
\+---------------------------------------------------------------------------------+

#### **功耗与热性能平衡（Power & Thermals）**

* **休眠与自旋控制**：严禁采用空循环自旋锁等待指令同步 22。当 emulated 线程在 Windows 环境下遭遇 x86 PAUSE 指令时，SDK 必须捕获该操作并翻译为 native ARM64 汇编中的 YIELD 指令 22。这可以减少 CPU 高频轮询带来的不必要发热，降低设备在运行大型开放世界时的过热限频降帧概率。  
* **屏障屏障最小化**：针对 x86 TSO（Total Store Ordering）强内存模型的模拟，必须限制全局内存屏障的使用。默认应根据 PE 内置的 Volatile 元数据，仅在涉及多线程不确定冲突竞争的数据物理地址读写时插入 ARM64 物理内存屏障指令，避免全时指令管线刷写，使整体翻译功耗降低 ![][image15] 18。

### **2.4 系统集成与安全合规需求**

#### **权限声明与申请规程**

宿主 HAP 必须在 module.json5 的权限声明数组中明确注入系统级受限特许权限，即申请启用鸿蒙内置运行时引擎的 JIT 编译功能 14。该权限仅对经华为核准的合规游戏发行商企业级开发者账号开放，不支持个人开发者级调试和部署 14。

#### **签名验证要求**

要求使用开发证书签名来激活JIT。要获得Release证书，可能需要找余总。

#### **开放源代码合规审计**

鉴于 SDK 内部依赖了诸如 Box64、Wine、DXVK 等开源组件，该 HSP 在通过 AppGallery 提审前，必须先在 HDC 客户端工具链下调用静态扫描命令进行合规性检测 2：

Bash  
hdc oss-check \--path./src \--license LGPL-2.1/MIT

确保所有的动态重写及包装函数在发布声明文件中清晰披露开源版权，防止因 GPL/LGPL 强传染性开源协议而导致应用被下架 7。

## **3\. 架构设计与技术实现细节**

### **3.1 用户态PE镜像加载与IAT映射机制**

用户态 PE 加载器是实现免除系统底层二进制动态加载拦截（绕过 dlopen 限制）的核心防线 6。其核心技术机制由两部分组成：

#### **自研 PE 格式内存布局重构机制**

加载器直接跳过宿主 OS 调用，通过调用鸿蒙标准的 NDK 文件系统读取接口，以二进制文件流格式读取只读资源包内的 YuanShen.exe 以及相关 DLL。

C++  
// 虚拟代码逻辑：用户态 PE 映射  
void\* map\_pe\_image(const char\* asset\_path) {  
    RawFile\* file \= OpenAssetFile(asset\_path);  
    IMAGE\_DOS\_HEADER dos\_header;  
    ReadFileData(file, \&dos\_header, sizeof(IMAGE\_DOS\_HEADER));  
      
    IMAGE\_NT\_HEADERS nt\_headers;  
    ReadFileDataAtOffset(file, dos\_header.e\_lfanew, \&nt\_headers, sizeof(IMAGE\_NT\_HEADERS));  
      
    // 匿名物理页映射开辟，完全处于用户态，鸿蒙底层安全沙盒无感  
    void\* preferred\_base \= (void\*)nt\_headers.OptionalHeader.ImageBase;  
    size\_t size\_of\_image \= nt\_headers.OptionalHeader.SizeOfImage;  
    void\* allocated\_address \= mmap(preferred\_base, size\_of\_image, PROT\_READ | PROT\_WRITE, MAP\_PRIVATE | MAP\_ANONYMOUS, \-1, 0);  
      
    // 自主计算实际偏移并执行内存拷录  
    IMAGE\_SECTION\_HEADER section;  
    for (int i \= 0; i \< nt\_headers.FileHeader.NumberOfSections; i++) {  
        ReadFileSection(file, \&section);  
        void\* section\_destination \= (void\*)((uintptr\_t)allocated\_address \+ section.VirtualAddress);  
        CopySectionDataToMemory(file, section.PointerToRawData, section\_destination, section.SizeOfRawData);  
    }  
    return allocated\_address;  
}

#### **地址重定位（ASLR）与 RVA 重新映射**

当实际分配的首地址 ![][image16] 无法契合 PE 预置的理想基址 ![][image17] 时，加载器需手动迭代处理 .reloc 重定位节区，根据地址偏移变量执行地址修补 9：  
![][image18]  
对于重定位表中的每一处需要修改的绝对虚地址 ![][image19]，其修正计算公式定义为：  
![][image20]

#### **符号桥接绑定**

读取 PE 结构中导入地址表（Import Address Table, IAT）的每个函数导入入口，在加载器符号缓存中检索对应的宿主桩函数（Wine Ntdll / Kernel32 鸿蒙 AArch64 原生实现） 9。检索到匹配符号后，直接在用户态物理页中复写该导入入口的地址指针，彻底切断对 Windows 物理 DLL 底层加载链的依赖 9。

\+---------------------------------------------------------------------------------+  
|                       用户态 IAT 桥接重映射技术                                 |  
\+---------------------------------------------------------------------------------+  
|                                              |  
|         │                                                                       |  
|         └── 导入函数: CreateFileW (IAT Entry Point)                             |  
|                    │                                                            |  
|                    ▼ (用户态加载器手动拦截并重定向)                             |  
|                    │                                                            |  
|   |  
|         │                                                                       |  
|         └── AArch64 原生桩函数: CreateFileW\_Shim(...)                            |  
|                    │                                                            |  
|                    ▼ (系统调用转换)                                             |  
|                    │                                                            |  
|  \[鸿蒙底层标准 API (musl libc Fork 系统调用接口)\]                       |  
|         │                                                                       |  
|         └── POSIX 原生系统调用: open(...)                                        |  
\+---------------------------------------------------------------------------------+

### **3.2 W^X约束下的双重映射内存管理**

为了在鸿蒙 NEXT 强制性的 ![][image2] 安全保护页表级别限制下，正常启用 Box64 等翻译器的 JIT 动态代码生成，SDK 在获得系统特许 JIT 编译权限后，必须在底层建立高级“双重映射”内存管理器 1。  
该内存管理器的核心逻辑是利用底层操作系统的虚拟内存分配能力，将同一块物理内存框架同时映射至当前的鸿蒙用户进程地址空间中的两处不同虚拟段：

C++  
// 虚拟代码逻辑：双重映射配置  
struct JitPage {  
    void\* write\_view;    // 映射视图A：属性设为 PROT\_READ | PROT\_WRITE  
    void\* execute\_view;  // 映射视图B：属性设为 PROT\_READ | PROT\_EXEC  
};

JitPage allocate\_jit\_page(size\_t page\_size) {  
    // 建立底层的匿名共享物理内存句柄  
    int fd \= ashmem\_create\_region("jit\_cache", page\_size);  
    ashmem\_set\_prot\_region(fd, PROT\_READ | PROT\_WRITE | PROT\_EXEC);

    JitPage page;  
    // 第一次映射：只写只读视图，用来向其中灌入重编译生成的 ARM64 汇编字节  
    page.write\_view \= mmap(NULL, page\_size, PROT\_READ | PROT\_WRITE, MAP\_SHARED, fd, 0);  
      
    // 第二次映射：只读可执行视图，提供给 CPU 执行线程，JIT 引擎生成代码后直接跳转至此视图执行  
    page.execute\_view \= mmap(NULL, page\_size, PROT\_READ | PROT\_EXEC, MAP\_SHARED, fd, 0);  
      
    close(fd);  
    return page;  
}

\+---------------------------------------------------------------------------------+  
|                       W^X 规避：双重虚拟映射地址变换                             |  
\+---------------------------------------------------------------------------------+  
|                                                                                 |  
|                      ┌─────────────────────────────────┐                        |  
|                      │ 共享物理内存框架 (Physical RAM)  │                        |  
|                      └────────────────┬────────────────┘                        |  
|                                       │                                         |  
|                 ┌─────────────────────┴─────────────────────┐                   |  
|                 ▼                                           ▼                   |  
|  ┌─────────────────────────────┐             ┌─────────────────────────────┐    |  
|  │    虚拟映射A (JIT 写入端)    │             │    虚拟映射B (CPU 执行端)    │    |  
|  │                             │             │                             │    |  
|  │  \[虚拟地址: 0x7000000000\]   │             │  \[虚拟地址: 0x8000000000\]   │    |  
|  │  页表属性: PROT\_READ/WRITE  │             │  页表属性: PROT\_READ/EXEC   │    |  
|  └──────────────┬──────────────┘             └──────────────┬──────────────┘    |  
|                 │                                           │                   |  
|                 ▼ (DynaRec JIT 动态写入)                    ▼ (程序计数器 PC 跳转)  |  
|          \[写 AArch64 代码\]                             \[执行 translated 机器指令\]  |  
|                                                                                 |  
\+---------------------------------------------------------------------------------+

通过这套内存拓扑设计，当 DynaRec 发现一个未翻译的 ![][image21] 基本块时，翻译线程向 ![][image22]（如 0x7000000000）写入转译后的 AArch64 汇编字节 3。写入完成后，翻译引擎不需要调用代价极高的 mprotect() 转换属性、也不需要清除当前的 D-Cache 转换锁。  
引擎只需计算出对应物理位置在可执行映射区中的相对地址，并将虚拟处理器程序计数器（Program Counter）重写为 ![][image23] 的对应地址（如 0x8000000000）直接执行：  
![][image24]  
这一设计从物理架构层满足了鸿蒙微内核对 ![][image2] 页表保护的要求，同时实现了零开销（物理零重置页面属性延迟）的 JIT 动态指令生成，平抑了运行时因反复修改页表造成的性能抖动。

### **3.3 国服原神反作弊（ACE）特定兼容层实现**

国服《原神》之所以在传统 Wine/Proton 中会出现卡死、封号或直接报错崩溃，主因在于 ACE 无法顺利获得对内核驱动程序的控制应答 15。  
在对国服反作弊进行针对性的用户态解耦时，SDK 将在 Windows 环境的初始化流程（即 NtLoadDriver 系统调用映射）中专门注册一个 Hook 钩子 11。当游戏客户端尝试通过 DeviceIoControl 或系统调用加载 mhyprot2.sys 驱动时，SDK 并不启动真正的内核注册链，而是通过反作弊兼容层向客户端发送完全符合其协议逻辑的结构体应答 9：

C++  
// 虚拟代码逻辑：拦截驱动加载  
NTSTATUS hook\_NtLoadDriver(PUNICODE\_STRING DriverServiceName) {  
    if (wcsstr(DriverServiceName-\>Buffer, L"mhyprot2")\!= nullptr) {  
        // 监控到国服原神试图加载反作弊驱动  
        LogHilog("Intercepted mhyprot2 driver loading. Initializing user-space fake shim.");  
          
        // 注册用户态假的驱动通信机制  
        RegisterFakeDeviceIoControlHandler();  
          
        // 恒定返回 NT\_SUCCESS 告知游戏客户端“驱动已加载就绪”  
        return STATUS\_SUCCESS;  
    }  
    return NativeNtLoadDriver(DriverServiceName);  
}

针对后续用户态反作弊机制对 Steam Deck 硬件豁免特征的扫描，SDK 必须接管底层关于环境信息的查询接口，实现高度逼真的“沙盒模拟” 16。在 Wine 初始化时，SDK 将向 emulated 环境主动注入以下底层环境变量 17：

Ini, TOML  
STEAM\_DECK\=1  
STEAMOS\=1

同时，当 ACE-Base.dll 底层调用 Windows API 读取显卡物理标识（如 dxgi 下的硬件适配器描述符）或进行 EDID（扩展显示标识数据）物理设备 IO 捕获时，图形翻译适配器将拦截该请求，并重写硬件名称、厂商 ID 等核心属性 11。  
具体映射关系如下表所示：

| 底层硬件/系统字段 | 游戏读取到的原始数据 (Windows) | SDK 拦截并重写的伪装值 (Steam Deck 仿真) |
| :---- | :---- | :---- |
| **GPU Vendor ID** | 原生鸿蒙设备硬件 GPU 厂商 ID (如 Hisilicon) | 0x1002 (AMD 厂商 ID) |
| **GPU Device ID** | 原生鸿蒙 GPU 系列代号 | 0x163F (Steam Deck Custom APU Aerith) |
| **System BIOS** | 鸿蒙 2合1/PC BIOS 信息 (或 Microkernel 特征) | Steam Deck Valve Corporation BIOS |
| **Monitor EDID** | 鸿蒙物理显示屏 EDID 字节码 | 特制的 128字节 Steam Deck LCD/OLED 标准屏 EDID 字节数据 16 |
| **OS Registry Base** | HKEY\_LOCAL\_MACHINE\\Software\\Microsoft\\Windows | 伪装成包含合规 Steam 客户端安装信息的定制注册表键值 11 |

通过上述对内核加载、系统环境变量以及底层硬件属性的一体化伪装与深度欺骗，SDK 内部的 Windows 应用程序能够与 ACE 建立安全审计互信通道，从而实现《原神》国服无需修改二进制文件即可在鸿蒙 2合1/PC 上稳定直接运行的技术构想 16。

#### **引用的著作**

1. A first look at app security on HarmonyOS NEXT \- Promon, 访问时间为 六月 1, 2026， [https://promon.io/security-news/harmonyos-next](https://promon.io/security-news/harmonyos-next)  
2. FEX-Emu/FEX: A fast usermode x86 and x86-64 emulator for Arm64 Linux \- GitHub, 访问时间为 六月 1, 2026， [https://github.com/FEX-Emu/FEX](https://github.com/FEX-Emu/FEX)  
3. Box64: Linux Userspace x86-64 Emulator with a Twist \- GitHub, 访问时间为 六月 1, 2026， [https://github.com/ptitseb/box64](https://github.com/ptitseb/box64)  
4. How To Integrate Native C++ Codes Into Arkts \- HUAWEI Developer Forum, 访问时间为 六月 1, 2026， [https://forums.developer.huawei.com/forumPortal/en/topic/0203190279174833076](https://forums.developer.huawei.com/forumPortal/en/topic/0203190279174833076)  
5. Document \- Huawei Developer, 访问时间为 六月 1, 2026， [https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/c-cpp-overview-V5](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V5/c-cpp-overview-V5)  
6. HarmonyOS 使用dlopen无法动态加载so？ （API12＋）-华为开发者问答 \- Huawei, 访问时间为 六月 1, 2026， [https://developer.huawei.com/consumer/cn/forum/topic/0203210593176919169](https://developer.huawei.com/consumer/cn/forum/topic/0203210593176919169)  
7. HarmonyOS Next application packaging and release \- DEV Community, 访问时间为 六月 1, 2026， [https://dev.to/liu\_yang\_fc0e605820ac220c/harmonyos-next-application-packaging-and-release-5h46](https://dev.to/liu_yang_fc0e605820ac220c/harmonyos-next-application-packaging-and-release-5h46)  
8. Developing a Dynamic Shared Package, 访问时间为 六月 1, 2026， [https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hsp](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hsp)  
9. Portable Executable \- Wikipedia, 访问时间为 六月 1, 2026， [https://en.wikipedia.org/wiki/Portable\_Executable](https://en.wikipedia.org/wiki/Portable_Executable)  
10. PE loader source code? : r/ReverseEngineering \- Reddit, 访问时间为 六月 1, 2026， [https://www.reddit.com/r/ReverseEngineering/comments/das9e/pe\_loader\_source\_code/](https://www.reddit.com/r/ReverseEngineering/comments/das9e/pe_loader_source_code/)  
11. Download Wine for Mac | MacUpdate, 访问时间为 六月 1, 2026， [https://wine.macupdate.com/](https://wine.macupdate.com/)  
12. Wine on macOS State of the Union \- WineConf 2022 \- Indico, 访问时间为 六月 1, 2026， [https://indico.freedesktop.org/event/2/contributions/92/attachments/87/140/Wine%20on%20macOS%20State%20of%20the%20Union%20-%20WineConf%202022.pdf](https://indico.freedesktop.org/event/2/contributions/92/attachments/87/140/Wine%20on%20macOS%20State%20of%20the%20Union%20-%20WineConf%202022.pdf)  
13. FEX 2605 Tagged – FEX-Emu – A fast linux usermode x86 and x86-64 emulator, 访问时间为 六月 1, 2026， [https://fex-emu.com/FEX-2605/](https://fex-emu.com/FEX-2605/)  
14. Restricted Permissions-Application Permissions-Application Permission Management-Application Access Control-Security-System \- HWdeveloper \- Huawei Developer, 访问时间为 六月 1, 2026， [https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions)  
15. Kernel level anticheat and Linux: how it works? \- \#9 by snowyyd \- Fedora Discussion, 访问时间为 六月 1, 2026， [https://discussion.fedoraproject.org/t/kernel-level-anticheat-and-linux-how-it-works/162491/9](https://discussion.fedoraproject.org/t/kernel-level-anticheat-and-linux-how-it-works/162491/9)  
16. I finally got burned by anti-cheat. Official Linux support may be worse than none. \- Reddit, 访问时间为 六月 1, 2026， [https://www.reddit.com/r/linux\_gaming/comments/1hpvn2z/i\_finally\_got\_burned\_by\_anticheat\_official\_linux/](https://www.reddit.com/r/linux_gaming/comments/1hpvn2z/i_finally_got_burned_by_anticheat_official_linux/)  
17. Anti-cheat stops Mecha BREAK running on Desktop Linux but works on Steam Deck, 访问时间为 六月 1, 2026， [https://www.gamingonlinux.com/2025/02/anti-cheat-stops-mecha-break-running-on-desktop-linux-but-works-on-steam-deck/](https://www.gamingonlinux.com/2025/02/anti-cheat-stops-mecha-break-running-on-desktop-linux-but-works-on-steam-deck/)  
18. Releases · ptitSeb/box64 \- GitHub, 访问时间为 六月 1, 2026， [https://github.com/ptitSeb/box64/releases](https://github.com/ptitSeb/box64/releases)  
19. Box64 vs FEX emulation performance on ARM Cortex-A53 \- UoWPrint Blog, 访问时间为 六月 1, 2026， [https://printserver.ink/blog/box64-vs-fex/](https://printserver.ink/blog/box64-vs-fex/)  
20. How to Build Dynamic Widgets in HarmonyOS Next: A Step-by-Step Guide, 访问时间为 六月 1, 2026， [https://dev.to/harmonyos/how-to-build-dynamic-widgets-in-harmonyos-next-a-step-by-step-guide-5hgn](https://dev.to/harmonyos/how-to-build-dynamic-widgets-in-harmonyos-next-a-step-by-step-guide-5hgn)  
21. FEX 2604 Tagged, 访问时间为 六月 1, 2026， [https://fex-emu.com/FEX-2604/](https://fex-emu.com/FEX-2604/)  
22. box64/docs/USAGE.md at main \- GitHub, 访问时间为 六月 1, 2026， [https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md](https://github.com/ptitSeb/box64/blob/main/docs/USAGE.md)  
23. harmony 鸿蒙Bundle Manager \- seaxiang, 访问时间为 六月 1, 2026， [https://www.seaxiang.com/blog/5c16a5cf1ee24fcfac37ce52c4ebcd04](https://www.seaxiang.com/blog/5c16a5cf1ee24fcfac37ce52c4ebcd04)  
24. Writing and Publishing Your Own Third-Party Library for HarmonyOS Next | by Muaz Kartal | Huawei Developers | Medium, 访问时间为 六月 1, 2026， [https://medium.com/huawei-developers/writing-and-publishing-your-own-third-party-library-for-harmonyos-next-cff89bb4ded1](https://medium.com/huawei-developers/writing-and-publishing-your-own-third-party-library-for-harmonyos-next-cff89bb4ded1)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGcAAAAZCAYAAAAsaTBIAAACwklEQVR4Xu2YvWsVQRTFryKKIoYoElGwCiGJNipKQBtBNGgjWAiiYArBwloQkQgKYmFjISHBQgsLRQsLNSgIgoKITbCzeV2K/BF6jrMDs9eZzbx9M0uU+cFh9927j5m9Zz52V6RQKBQK/wAboJnqWMjEdmhHC9GYX9B9KXTOGegndBJar3L/HWPQtIpthI6o2FpgnRhjVqADYpauyeo4CKPQOR10GIeuQVegvSqXlbNilgFX72pXrA0eiTGFS5eGMeYvQptULsRhaLkS73munv4DTb8BHXdiPGds0AERxTExo5Gd/Aadkvgb7ALOFs7i19AhlXNhn2neM50IsBM6CG2RsDlTUE/q9eA569XJykJzfB2LYZ80j6BtYorQBu4n16GP0IKY2Ux9lvosfwXNipk1e6Cb0BNoSOIJmfNGTE7D2AsVy1KLQczhcsIC+jrF3Lz4c7Fw5LIQnNXWBM5sjlqOeB9bxfyH18USMue7hM35qmJZakFzPkC3oRNiRh2nLZeTGHZBz6XeMDuTc12mMV+gCZ2o4Cjtp+2QOXZ2akLx5LWwe45lWEwD7ia4GuyU7UDrUdIHNOet+B8O2pDKHJK0FnZjdLkKvRTzIhgLDWWn2BkecxIy5zx0WsViSGkOyVoLziY2fkknGrBTmhtyqqc97h/2QcDVoph9iMuxzlFH+ec+CJnDpz+fCYz1dNAhWS0+Qe9VrI05WUeLIjRz2hIyp58HApdktWBDP1TsMrQE7VdxH3aUJNsEI+jKnDsSNueWDkqGWvAmR53fnIYPoQfV+Wo8Ff/oGHjUNNCVOVPy90so2w69hCavBdf1u2I+f8yK6ejj2hVhsrx4RdBkDvvDe+De0wS/l/E6n1xYH+5v9yr1oM3uBRXZasF3Gn7Uo7v8sBf7jpMLtq83+TbaLWlgTVifC9CIyhUKhUKhUCjk4TdTj7cCvv9OhgAAAABJRU5ErkJggg==>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAaCAYAAAAHfFpPAAACa0lEQVR4Xu2Xz6tNURTHv35LJAxIfjxElGLyZGCAElOSEmaKKUkZSHllRHi90ZNkQhJTFKWMDBhIUiZvZuCPYH2svbvnLvfed84ub7Q/9e3dvda9u3XWWnvt86RKpVKpVJaG9QrT/KRlwTeKhdHwH1kcDQ2IY1FjPS+s/2GN6YTpt+mWaZX84dlotelb8m1P6wy/O2V6bToo/81cQWG2mZ7KY7usXgFIzmHTT9N9eZyjEvaXPfKNzkWH8UruG7TJTtOGaGzBEtOmaCzgiDy2iWA/ZhoPtpFQXTa6ER1yO4rHYZ9pOtjasEAe8AvT+uDrCu2d48u8Mx1qrFtBm7DJ3WCnul+Tj+80mZK3fle2mp6bJk0ng6+EL/L4lpt2mM7KE9MJqssmDxq2vaYn8q7AN9bwrZW3fwlUfrc84IfBV8JR9brgWvC1JieA8565bTquXgLyA5PdC+lvCXfkMwDogPy5FI7RG9N708Z+Vzd4yI/p80r5GQcGI74DaX092UpgaFH5JswD5kIpV03f5TE+Cr5OsMGn9JnK52vldPLlBDD4SFBXhrX8S/lcKIEu5Ehtlsc40+ftSD5Hl+QtnuHBsVN1rpfSlqXS56NRPg94iK4w6Zn4GY4BcRbfLDkBj+VDLrPL9Nl0M/lKeabBwZFQ5kJX4nV3RR5/8c3yS75BbO8x0wfTW5W99AAPTqWHwfFgPrSBgvD2GYcwieRqnTHt73e1g/P/Ixrl9z+3Q+ngA6oy26C7p9HHa4v8yuMVl0LxJtlMAkeVaxsfs2adBr+9DuWiBrcom5yJxg7QUfzPMBt0ANWtVCqVSmUO+AOLc2VejDnhCwAAAABJRU5ErkJggg==>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAWCAYAAABHcFUAAAABlUlEQVR4Xu2VTysGURTGj8j/EhYslY0/+QBCsZCFbBWlrGRhw06ysbJTFrZ2krJBsVFSxMLOzkfwIXiezpzeM2dMMyZ286unt/uc89577pl7Z0RqampqMnRA+9AJdAp9QS9Qk0/KYQf6hB6gO+hJ9P/DLqcSu6IFGQeiE885Lw8WxVyvs1RGRWwyz2biLQQ/shaNv8KKanUei6FXtGhR3ODcG9F08KgUPhk7KzMxEGBRXdCy6Hnkb08qowEXvofGSvop+qBL6ALqDbEIi7oR3QR3egW9pTLSrEKPbsyCFqWgIPIMfUQzh6EwboYOoWOoLcQMFsLCxqVEh8ig6E6nYuAXsGucYyQGHOwYNz4RAxG+Gq7duDNRHrPQu+hGPHykvCTTwTdKd6oFOpf0Anxfrbhx5Eh08aXgr4teksngExbELlkhPE8sLAMPKNvNTnm9SuMRcDIW4M/avOhl8Ngl2ZbsFyHvlv3o8xHEtzJ1C/UnOe3ON7pFvwT8TBl7ojmMeeyWjQbfyO1YVXg2tkS7OxBiNf/GNyvMUIT6ojq6AAAAAElFTkSuQmCC>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFMAAAAWCAYAAAC8J6DfAAAArUlEQVR4Xu3WMQrCMBiG4V8RRBdBr+BRXAXvILhIx97ETXB0c3LQ0VFwdetl/H7SpQGhSXUp7wPvkpAlhCRmAACgH7ZqHw+im1K91VINojlkmKmXOhkb+lNr9VArNWpOIYdv4s3Cpo6bU+jiqKp4EGn8QTqowsKdikRDdVFPNYnmkMAfHL8neXgy+enzU3i2cCqRaWPhb8lnHeitqVq0bF6vwRc7dW/ZtV4D/M8HKA4X1l1Xh+EAAAAASUVORK5CYII=>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADcAAAAWCAYAAABkKwTVAAAAqklEQVR4XmNgGAWjYBSMglFAfaACxF3ogkMZMAHxMiA+AcScaHJDGrgA8XYg9gVidjS5IQm4GSCxBIotUKwNG5ALxBeAWBuIGdHkhizIBuLXQMyPLjFcgDwQXwHiUnSJ4QZAHrzBACn6h03yRAagguU0EM9jGKYehAEvBkiVYMcwzEpQGAB5ai0Qb0KXGAWjgDaAC4iFicRCUD1DBqQB8Q4i8WaonlEwkAAAm/oX1CTaQVEAAAAASUVORK5CYII=>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFYAAAAZCAYAAACrWNlOAAADZUlEQVR4Xu2YzesNURjHv15K5CVECF2FiGRDKQl5WSnlpYiywoKFXygJRYpSSpLYSUgp9SsvsZCFlFjIQtn89v4Inu/vmcec3zPnzNy594bF+dS3O3NeZs75zpnnOXOBTCaTyWQy/x3jRLMTmikaXzaNwnbXRFdFi6HXO1Qc/1M48CHROeggYxyE1q8XTXR1no2iX12KTImUe+0TTSrah+wRfRMdL46/iy6I3otWBO2SzIV2oBa4un74LLpXHPNJc5A3y2psEf1AaeY80fPit4nDUFP467HrhpjBL1054RhZF953lug1qn7Mh86rK2ONM9DJL4Ua0Q9LRG9FC4tzrlYO/smfFsAz0YfgnOwVnULz/euMnSC6grHXqDN2N7TuNMo+G0R3of08rY01Jov2Qye+ydV1A2/Km69z5dNQDpy/nMydsnoU9h1Bta8nZmxHtKo4XglddUadsRZeWGfhaqfoq2itNQp4iB6NNXaJ3om2oTn2hdikO8X5dFRXoE30kivnq8fyA67cEzP2CMrrzRBNLatqjd0MrQtX6OqibBjVsXM+bfxIwgTElfsRGuibeAAdFGMXHw7774CuTpushQZvbKrcY8Yeg/ZZBI2rqX4pY2kaV+ZPVM1ivGefUHyLvdF9cx/VpBCDg+cgzkPjHbFX/2xxnjIwVe4xY71S/cxYmsgdCMW2b6ALhg/ew6R+HdV7MA8MxFwms9uik9BXrAkz1sdJllmyShmYKvf4FTsH3a3Y0FiK2yi/Uj2MwRdRGss5LB/TogV8fbns+TSZzNrAWMUB+H2rDYwwscQMNGO5960jFmN57K9npEJBitSWj6GM12G4aw2TFQfQNmkZ/FJpMtYmermsHqVTlPeSvDoodwWetsbGtnFGm+uMrkquzkdo/sxrghmVr9wyV84BjQTnTBj+yXP/+AL6atcRM7aOXozlPGLwOuGHThJukD9hMB8GhJ+Ht0TbXTkHxFhtxD4QOKF+PxBimLH8muoGXpe7GG6tQpiMuSD83P4qfAO+iG5AE4sP+DSPGfYpNImwPc2uI/VfQWolmqFeqfYGjeWemrGei+4xdAdBU9vmnIHDAWyFDo5/sKTgXpcZmvGx3zA0KNYExwxPJ9DDv1p8qkw03Sj8TMw0cFT0qksNF30ymUwmU89vnPjnqEsjLP0AAAAASUVORK5CYII=>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABsAAAAZCAYAAADAHFVeAAABv0lEQVR4Xu2USytGQRjHH5FblEs2FlaSUKKwsVHERik7Ua+FYmsnuWZhY8GCt2RBVqSUBaLIwkZKsvMBfAz+/zMz5zxn3vNeFpbnV7/OeWbmzMwzlyOSkvKPvMJVWAvv4WS8OqAGbsE6v8LRASe8sko4qOIqMQO02ngO/sIxiTrm8xa+2ziRKTEfau9iLUSG4TYss3E9PIyqQ7JSICvCjr7hD3yD42Iy0TCTDRVzKdmxpgt2e2U5cDD/Q59eMZlU27gFnkfVMivF+wgoZbAmeAkbbMy9Ooqq5UZKyIpwsEe4CUfhqZhldfvjmIYf8BnOwwoxbZhVwX3SuD1zNMILOKLKHDylzSrmPl2rmNmtwz7JnWwA17/fK1uEV2KWrxBcfmZG2PkXXBIzgaTJJsJseQV4CvPBLJiZYxkO2PdyuKvqQl7gg1dWbDDuEbNyS8WrcAw7wxZ5vmWnTF+TgZ+wxyt38PTprLiP/HvowXhfc2CjdhXzQh/APfvuw6y4T/oAJGWWUe8h/HhHzKXlX4KZnsRaRHCfmFUS/MeuibkSPBxn8eoIznIBrsA2G/tw9rzIM36FgvdwHz7BIa8uJSU/fzzjQ4P24pYtAAAAAElFTkSuQmCC>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACkAAAAZCAYAAACsGgdbAAAByElEQVR4Xu2VvytGURjHHz8ikp8pRWIRFlJEYbCQyWBlM1pkMcigZGBQksVgJZMiKyULk83y7v4Ivt/OOe5zn/ve2xvqKvdTn173Oed97/ee89xDpKCg4H9QBQfhFlwzY3+CAXgN+/z1FLyErWFC3rTBCzjqrxvhKbyHvWFS3tzAD1Pj1lebWq68w5L/m8EqDdcBu2C9vx6Gs7D7a4ZIO5yGLaqmmRDX/3wX2Fo18WEHi1zFF3GTecMR+CguQBp1cF3cAx5J9KLVwj246+vcEcJ+59wAw72pa35vW1yrJWCRIamesAyPTc3Cp3+GhxKtJpkX93urqrbja4EVc034spa9nw6p4WqW4KSpa0JIhtJwex8kOilIWsgeiVa7WVK2m3Ayb6ZhANZPTF0TQnIFNAx5K65nAzYkgy36WvBJjSfICsmjKI0Qkp+arJB2pRbgvh+j/fHhiDuJNzUZEvelJVPXfCdk6DluN8NpZny9LJuS7En22RXsNHVNCMlQmkpD8gTRjEuyv2Pw3yKPhANxx1Fmf4gLovuJhpdBOyauZXSND8C5Z+LuxZ18hedSATy7NuAcbDBjvw0Ped6D5y1XvCk+XFBQ8CM+AerWYisWg2z3AAAAAElFTkSuQmCC>

[image9]: <data:image/png;base64,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>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEoAAAAZCAYAAACWyrgoAAAC40lEQVR4Xu2Xy8tNURjGH/f7PXIZ+FySSIqJAUoRKUUhAwZKKCMKSTJxSZGJZEIxMJFyGTBRoqRMJSV15v4Inqd3L3vtt++cvdbZR059+1dP39lrrbPP2s9+L+sDWlpaWgbKOOoW1aGmVKewlfpNLXXjY47t1GOYGV+pC9TUaD4YNeaYQJ2ijlKbqAfUm8qKKkNr1CFqxA/WsIC6BIuGaW6ujm5Gych1KI2aRO2urGiI8n099YU67uZGQ2F+DbaZ78VfbS6Vd9SG6Poy9Sm6riM2SoaL6dRH2AuLI0rPpnvLwEaMp55Sn5H+ZpUKSoFlsA3kGDWHOubG5lPPYfdNIRi1mHpBLYEVbo3LMJ96L4t12ahL7INtToWxCWuRZ5TWa9N6yMAs6gk1ORrrhX7Pp95plOnvjVoJi6qsLjgDFj2KIkVTU3KN0ma1/gMsLcRO6sffFb2Rqfr++2hMUaRoCvfzRoV57bUnyuPz1D1qtZtrSq5R4ibsO9JPag/SX9oJlBH1DVbAD1JnozXeqIvUjui6K2eoX7D6MGj6MUrNQAU8mHWbWlRZMTohRZ/BjLoBi0Tda160zhvVgUVw0vMvhx3OFFmDpB+jrsA6bDg0hlSsYwvsGUIx13UH1gxiYqOUdvrsG0gSMkttXWkY8rpfco06AEu1mPuwe+xy45631Ap0P0d5FsIa1jY/kYOKut7qIzQzK8eoUFT1AH78LnXOjcfMRFlnUo3SgVZ7Sz121LIX9sM6KqQW1UAvo3QM2RxdhxozNxoLbKT2+8GCVbB/YQJ1RunFq5Pqt/xLaYwMUpi+8hM19DLqDmxuTXGtB1B30kPEaFxGKK1SqDPqMKzIh1P7f+UqykIcSw8ROALbcNyRxENYF1a3ug4r0IrqVLoZpUO0zoiK4iblZGhQ9I7AaojqUuq/TgFvlL6vKFIXjVM9GxVLhWGKfKsdRmZTE4vPOpMNjJOw1pqi18V3WlpaWv41fwBi1ZijIN315QAAAABJRU5ErkJggg==>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFMAAAAZCAYAAABNcRIKAAADG0lEQVR4Xu2Yz6tNURTHlx/5/SuSX8VNBvLKyI8UikiRgZgQSmGCRFGUlIGkDJSQohgYKIVXfgyUiJTMDJTJnfsjWJ/W3u+suzvn3PNu972u7E99u2+vvc45+6y99tr7PJFMJpPJZDKZOrarLqpOqJYnfZ5DqkuqDarJSV9kgZjfeTG/f5YJqiHVN9WxpK+MNar3YtfBRtUX1V3VrOikbFP9kiKAi1Uvwq8HP4LdzW/gmah6qvqqmp70VXFT9SCxHVH9UR13tudiQfYcUJ2TYiLmi/mtHPEwuBd+A89U1V6xl9ia9DWBrORl1zvb7GB7E9oEizbZ6lmtaotdi88VMb9pzge+i/kNNDPFspBsJCt7gYxpS+eSToM5I7SvjngYS4P9oJjP/dBOiRNWBc+mzq4TS44pYuVnmXS+12aprsHcg3p/WDVPtaOzuxweekF1R7Uq6esXLN/fqn2hzTPLgunt/E3wy4JWZY9QT8+oPqhuiwUUrotdhy0GZ4nY2HaGNlDL97g2K4SJ7copsZvNTTv6xCLVS9U1KTaRsQ4mUDLwueVsu4LtqBR1GdKx0CZrI5tU91y7lhWqH2IZ2m/YiRmcX/bjGUwCGCFA2FrOBulYaLOJxoDPUa0tuptDQH+KLXk/e73AseasFMsswi6dvgDEYHKexGc4tFOaBpMVR1ZFYjB5jicdy26x5MKO2Ef8fUYFGxHnykfSe0Ap+J+lWNoU/lhK4gbE0ve0gj3dgNIxfAr2Oggmuz6/kbpg3khsjBUbcaD/Y2d3bzBLZALHpKY7PBsABdwHgeXmizhZ88S1gdl/rVoY2mwK+HEa8GDDr47RBtOPjSBOcu0tYs/sCwSRc+ertKMEaiPnx8ti9TKK44xfSmWHdg73/Tq0x5rpN5KmwWRc/pmce9uuPW6QDbHWpPIvRsA4Mj1T7RerSwQuBT+OKvhx8sCv5R1KSJ/LJMWvsCjGGctIFCuQQD8Um6x3qreqx1L//4WBga8tMndIqssI9Qu/02J+Y038dCawaRbXQqGPF3UTyy5Tw0mxVG6i4XBNJpPJ/G/8BXQYw28zA/AIAAAAAElFTkSuQmCC>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFMAAAAZCAYAAABNcRIKAAAC6klEQVR4Xu2Xz6tNURTHlx/5/VvKj+ImSl4ZoRRKEZGBmBDKAAPegDIwkDKQiYESUoiBASl55cdAiZKSmYEyeXN/BOvT2uvdfdc7975z73u897I/9e29vfa65+zz3evsvY9IoVAoFAqFQl0OqdbHYOKY6rJqq2p66HOWiuVdFMubtExR9am+qk6FvjrcVP1WbQjxXaqf0jRwuepl+ptDHmaPlDfhmap6qvqimh366vJLqs18ofocYkdUF8QmEJaI5a0dyjC4HnkTnpmqg2IPsTP0dQOVdF21Q4abiVnE7mQxIGdQtUUs54pY3qwsB76J5U1o5opVIdVIVY6GfapHqu0y3Mw5KXY1i8HKFD8qlnMvtSPvpTruzBNbZzeLFccM1UbVKml9LsbWbg3mGqdVx1WLVLtbu6vhppdUt1XrQl+vUJVnxaqrykzuWWVmHuf/N6kdaRd3WE/7VR9Ut8QMBd4UfkfMzVkhthTtSW1gLT+QtXlDmNgROSd2sYWxYxQw0MXp//EwE7gfOWyAzt4UOynNdRniWGgzbmeb6m7W7sga1XexCh0tzPTzrD3eZmKg42NpZDGIY6F9X5qGL1BtanbXB0N/iL3y+ezV5Yk0qxKqzGSXjg8AbibnSXIGUjtS10zeOKrK8bFwn5w4lv1ixUUcsY/k1+kKNiLOlQ+le0N9AO0EvgFdS22nkeJxA4pj+JTincBMdv18EjuZeSPEWPaI4QP9H1u7e4NZohI4JvWyw58QG0z+UEDVUMU5zP5r1bLUZlMgb/5QhkGMvE50a2a+wWDitKzN8Y57jgmYyLnzVeyoQTszqw7t5I7Vod3XzHwjqWsm48rvybl3MGv/c7wyGGguB8P44nmmOiy2LmFchDyOKuRx8iCvkSdUEO/JJPmkuhibLyMu3kCMfiA2We9Ub1WPVatlEsDXFt/efdJ+GWH9Iu+8WN7fxj+dMTZWcUdY6P1HI4nXrtCBM2KlXEcD6TeFQqHwv/EHo2HD+ElbLKwAAAAASUVORK5CYII=>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFMAAAAZCAYAAABNcRIKAAADMUlEQVR4Xu2Yz6tNURTHlx/5/VvKj+ImCq8MhJIfpYhIERNCDJ4UBhRlIIVkYqCEFPUMDBTJKz+SEiUlExkokzv3R7A+rb3vXXd37rn3du97ruxPfbtvr73OOXuvvc/a6zyRTCaTyWQymTLWq86pDqsqjV0NHFJdFPMfn/RF5or5cT/8/lnGqAZUX1THk74iFqieqcaF9kzVkOqJanZ0Uraqfko9gPNVz8OvBz+C3cqv7xmreqz6rJqc9DVjr+q3ap+zHQu2Hc72VPXJteGA6qzYAsIcMb+lNQ+De+HX90xU7RGbxJakrx1Wqj6oNjnbSbEAEGggWLTv1DyMFaqqap2YzyUxv0nOB76K+fU1U8V2IbuRXdkLpqjuqd6oFjobQbocnQL0Yz8o9etop7yTYntkmlieXSu2OSaoVqkWSeO8WPBmOZh7DIrl/FmqbY3dxfDQ86rbqmVJXzeQK9eovostUHx1gWcWBdPb+ftVaKc0s0fIp2dU71W3xAIK18WuwxaDQ47/pdoe2kAu3+3avCEsbEtOid2MyfeSa6rXqm9iE/OMdDCBlIHPTWcjZ2M7Ko2Lm46Ftk9TG1R3XbuUJWI7iB3aa9jtw6r9Up/AaAbTH3oECFvF2SAdC+37Uh/vDNXqenf7ENAfYkHwq9cNFbEBcqgBp3Q6AYjBpJ7Eh0UoClq7weSNY1dFYjB5jicdyy6xzYUdkab8fTqCg4i68qF0HlAGurHAxqCqoR0PoCvRIVAJ9vQASsfwMdjLIJic+vxGyoJ5I7GR9rARB/qpULqGVWInUCa1c8LH1fSTWB5sBCHCrnnk2sDqv1TNC20OBfym1zwMbPiV0Wkw/QFDEONHB2wWe2ZPIIi8oi/SjgIoxBkcpUWEwWC76mxFRfsR6V3RHnOmP0jaDSbj8s+k7q269qhBGcLp/VYsD5FvWNV0AgSMLx4+Mzmc8Is51YMfpQp+VB74VbxDAfHtiGKRkLexa2MaieINZJwPxBaL2piKZEi1WP4iO1UXxP5BQS3XDL62+PYekOZphPyF32kxv5EmfjoT2HQTlEKijxe1Eq9dpoQTYlu5HQ2HazKZTOZ/4w/DLMSTtG9tBgAAAABJRU5ErkJggg==>

[image14]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFsAAAAZCAYAAABeplL+AAADXklEQVR4Xu2Yy6vNURTHl0fklVcUk3uTgcdMEXkUJXVLUTJioCSllHeS5DGQQkkScmVggpI7QIZKSgxkoEzMDPwRrI99VmefdfY5Z/9+53SJ/alv5/Zb++yz9ne/1u+KFAqFQqFQ+K+Yp5rfEH/3Yro026MJqsnumWl24zt/BVNUO1QTo2ckv0s1M3oWw8CG/cMG9LNSdVp1VLWmNZzkg+pnpCWt4TbitgjzlyWex/qhGlFNlQGCUQz2vWqfi6WYo3os7YlNixsplyT0+UVCfENr+DdMzhlpDmih6o7qrWqFNerCA9UN1ah0nujVqssS8mTlesiL2F4fUL5Jc3L6hlX1SPVO2s3qBD98W4KR31WnVEMtLQKrVJskmMZKTJm9XYIZTLhhKw4De0Ee2ySYQj8e+j2uOie9zU7ld1dCLNV3FqwiBvlUghlVMbNzwbyU2ZOkueI4PmJsx/SCPMiHtq9cDLaqjkl9s69LiG30gRxmSFjFrOb4zK3CoMyG9arXquXueVWzP0m6/RXVWqlvNscZsbk+0Al+4ITqpmqpi9XBzB5T7VYdVH1WLYgbRXQzOwWXHQO86gMJzGwubL7Db8Xsb3zmmH1ItbkhjsaPqj0SFmg2dMIFNaiSxsyOL6SdqlvumVHFbI4WLsyXqsUulsLMpi3HiJkL5GJVSo7ZLEYqIhO7/5qE4qESQxJWHyu8XzCEyy+GwZIw5Z+nitmsqq+SV4mAmc1FeFZClUS1BBwflKmQY7bPjz7Jm4VK6VoLDKcc40iJq4B+sEvqhQ9IvtnPVA9Vi3ygC2Y2zJKQw0UJk3/PGkk9s2FY9UbCrsnZaUk4hyjd7kt1w09KKLXi2e7XbLY89XVsRupI8sRmAzlgjFUhRl2zac+YyN/fB7UYkdAhZWBOhUJbkosHyeVoq8rTy2zOx/PuGavoiXuWglxiA3nBIQ9/p9Q1m0njGBmVvMnPApOpu5/7QAIM5UUhhvORszb1qt3NbHYV5dUFab2c2HGpXeLxZps5/u7IMZuXIw9HGzHukj/GOgn1MYPAZC5fvytsgF629a2q8XET3+8Ek5fqk8k7IuESh0450NbeVDuJSTss6Qkad7ZIOL/5zH3V/+dhFpmdHOX8u7LQhQMSXhJyNNb4TqFQKBTGl1+zfuUV047tGQAAAABJRU5ErkJggg==>

[image15]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAZCAYAAACPQVaOAAAChElEQVR4Xu2WzasPURzGHy+R97cI5T2FnY0UV5EoK0UWQhYWFuxwQ1JYKIqVsOBmQ+wQSZZEsrNQUnYW/giex3dO8z2nOTO/6XJR51NP93e+c+50nvm+zACFQqFQGBVD1GFqEvWC2hBdNeZRt6mJ6YWxZj81NQ3CDr+KGu9ii6i9bj2HekhNr9Znqe/URtj/i7nUW+pJtR5TZEAH1KE+Uc9hTz5lNvUj0UlqittzsIoHFlN33VpMoM7hL2V1JrWFmgU7bM6ssv2aeg/bMxxf/sV5xGZ1n/tuLbbCKmJgxlG7qWOoyyNH08FzdJndnAYTdiI2u5a649anYVkdGPXDJdSl9JE6EO2IWZMGWhit2ZXUG9QJOILY3CP0zOoItTCJLaW+UadcbAF1A9Yjg9JldgQ2WFSKR6l71Hy3R6gXv1CvqF2wKlRMWe3dpyrfJnbAptwz6grMvAZPH7rM6uGFSSs01BRL0V5/Dz2cB269ibpMrXCxRtanAcc02EB4R+2hJseXO2kzqwpJs6js+R7NofKVYaHsasjpFfeUWhc25VgG61VlT6XSZmp1GmihzWwTN2Fm2/ZvR9126uVr1PJqPYO6Vf1uRCXwAVaq4aX9GNYbKcrG7xhQyobmwYnqd6DLrIaRshpQZeiryu/X6yqLGj0dOjIqw8r2EtjNzlTrPuTMaq34dcRfVzq4zKbnCWhm+GGqB69E+ftr0GXJjX/163HEryT1bR9yZmXmYvXX85X6nMQCymro00CaWSXpQn35zxOyFh6Sl8x7NO1fwiawTO5D/K0cUJ/66esZog7BjOr74Gp8+d9B38HbYP2rvzlUvjLVhEyq6vTq0TTWt3mhUCj8P/wEMYhz3LVQyRQAAAAASUVORK5CYII=>

[image16]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGMAAAAZCAYAAAAlgpAyAAAD90lEQVR4Xu2Y26tNURTGh0vud4nk+kBuhaQIHZeklCKl6CiKCAmRPMiDhAe8SCJJuTy4JB5QR0eUSDx4kPKy3zz4Ixg/Y41zxprttc85+9gnnPXV115zzrHnnGt+c4w55hIpUaJEiRIlSvyT6K8cW4Ujo1GJnsEs5c8a/KFcrxzofyjReCwXW/ztaYOiItY2JKkv0SC4GPymuC7WtjhtKNEY1BLjkljbirShRGNQS4y3Ym2jk/oxyiblEeXqpC0CmwPKKcqJSRtYJNa+UCyh6PVwMfYrV2U8rvykbFYObTf9jRli9iez8rCsfLjNQmST8nMoY3MtlBnjm3JEVp6r/Kic0GbRS+FiXFaeCLyrvCi2UBFTxeyPhrqK8k0onxJb3Iit4blF7D+OfsrTyl2hrleiKEz1EVtQUtw0hCxTDg5l7OLiIwZ9Es4c48IzbS9CGWxUXlEOSupTDFD2DWVCKHV/C4gCsC4UiQGmie14Fi7G/DXKR8pW5RnlF8mLgXg7xfp1PsnaSJMpv5a8J0I8o1YazQYhnHI5dTB2tbl3FzOVS9PKTuCO2GasC7XE4KWfiS00l0TgZ8RDscUBtLMoKXy3uyDsYhfjarDrCrgPRTEYu9rcuwvmXu3u1RF4r4aIsVYsTN0UE4Gw81S5NxqJLYj34ZNJbXgxH6Mi+QPegTeRMOBZZFibxTKxiI7EGC/25YD/+WYB9En2tkE5KdQ3KXdL/jMQYZAEY4/YBophsVlsXhGMQ1IyW/6QGOvSBsVjsTYGAkViIFgqBp4TwU6bnz2TLGAfzyJeiKSA3wvKW2LeiNtHu1piYIcnkvGREHjGBx6IhcItYgsNpkt72GtVrszqEayivK3cJ7YRPfQypyXKbWJzpe2s2Prxv3dShxid+TZ1UPIvDvhWxct8V74S85o5YneSG2IHNZM5J5YeP1d+VZ6XPPAA+mGcD2KL7yCU+dnBPGO4KBJjlPK+5A9z5sFZx6WVzQDY5cOzZxbThabfeO7xHMflAkz/Dt6NcbGLm7NbnlEPeOHJYq7toYA6fyZU8JIsKAtXdChjw90i9gMQnFBwTyy97owYeMP7UA9YFA7hGCJTHBPzdryglhicnWnSwSHPxo12PS5Go1ERCwXAPcPDaJEYhAu81IXn7oJ3ElrnSX73kpazedjtnn67ZxB+SK9dDBeSEPoyswWcSWwksk2+RDj+OzEIXYQWwG3eFwUUiQH4z4LsmUPa7zJ4YIvYhRUgrIvh9x/OKfo6JCYoC4+AO8TE5HzBM/ww54sDY/CLZznog03wX4EF8fjflUsd4Y6wFzMgB/2kIRNb//aW/gfbGD6BZ5Up2CD0T391X/pKlCjh+AUeYNE3vi+NNQAAAABJRU5ErkJggg==>

[image17]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGQAAAAZCAYAAADHXotLAAADz0lEQVR4Xu2Y24tPURTHl0vkfss1l0kpoYQoIfeUUpQHigeihBTJJUmRQm5JEkk8eCDCKCSNiDeSBykvvzcP/gjWZ9ZZzvrt+c3PmJnfDzPnW9/O2Xuvvc8++7v3WusckQIFChQoUKBAl0Fv5YgKHBKNCtQPU5U/qvC7crWyr3coUB8sFBNgc9qgKIm19U/qC9QQLgjXFNfF2uamDQVqh2qCXBBrW5Q2FKgdqgnyTqxtWFI/XLlYuU+5LGmLwGa3cqJyXNIGiGPblfOV/ZK2bgsXZJdyacaDyg/KTcoBuWkzpojZH83KA7Py3l8WIuuUn0IZm2uhPE1M7PFZeayyMavv9nBBLisPB95RnldOz02bMUnMfn+oKynfhPIx5ftQBhvD/S2xMSK2KU8oeyX13Q6tuaweYotK+ss3S8QCKXcx2EUBEIQxcW2OkeGeMTmBESQOnJLYp7PQIC3fr5bAxfdMK9uK1gQBDWI7/7mUx4DlygfKJuVJ5WcpFwQBt4iN63wc2inj0uKJhHvEPk47C5w2Th1p+xmpz0cvG/mpdOA9qgnCoAzOYhOAgceM+2IPB7QjSoq1yiuSi+LJAfeMW2v4/OuNmgmyUsy93BQTAneCW9kRjcQE8TGuirms1IYPT38GAZ1xU2xVjlaOEbPto5wt+c5mA3CPyxyqnCW5O6WN/vxdcJCAvBBbHP+4JUnBbmZWpj/JBM+ZJ5YR8q7MYVRWju457e9gXvSnb6cIsiptUDwUayPzAq0JwuKmgnCCIjgt/hIHxOyZfMRFsV81TWLtuBnmheDrxQQijSb+4Cq5kt2xYGR9DWKCLBHDccldI6n1HOWjzO6s2PPJ8L4q72b23G8QmwPu7pDynNi8KvUHzA37Fcoj0k5B2vIvq5JPZ2JM+pvyldjp8TT2hljwRpBTYgv2TPlFeVrKwTi086y3Uh5jmFuMSZPFxvcMjD7xRN8T+4h1uItNXVZJ8r8OnBjmCbimro3+6e+kkrTsz/W2clBWD9olSEfATp0gdkw9jlDn97gdXAGTje4iBZkI7TBmJakgvrD+0qkg2D6RPDng1LDzKwnCqXO7NVn9nwiS9ucZeIX4jnUXpNZIBZkh5npiEuFJBrgktksdxA4SiEqCRNfMyQYIwqJGMH4aV0vSsj8bkRNKTHN0WUE8YBMfXufNze6UmOAgmJLluWDEKE5vKgixIArni4sgjaEeMIeNSV1r/T+KxQ8wWPlSKv8q+m/hguDG2Om+0L8DIqT/3SqhmhttCyr1Z64e5Dv0YfgvInVZBf4yPGjulJapcZfET4DB1RwIFiSgAAAAAElFTkSuQmCC>

[image18]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAwCAYAAACsRiaAAAAFF0lEQVR4Xu3c6autUxwH8GUIiYRkKGMRSl4pMpRShlJkyBCvFCXJWEL3hXlKhpBCV0oZypQhShGRvJF33tx3XvgjWN/WWnc/Huc6t3PP6Z5z7udTq72etfc+e6+1d+3v/a3nuaUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMCe47Da3psPrjOHzxr/NV2fg2b3AQAb3De1/V3blfM71pm8x/MmxzfXdv/kmLZGw1792BoBwCZwZG2v1fbX/I51JuHj1MnxgX2Mhfl65HOdjwEAG8zWST+BbT1vpc0D26e1HTE5/q22y2r7vba9+1juz3bvA2URSFN5+qmPfdLHNotpODuhH4812re2p2q7rbY/+1i8UdtVpa3HqGCeW9sXfeyUPgYA7AYJZ7dMji8prSKz1t6q7cv/aTuS8PF0aSHiwdp++ffd28PKFbW93/sJHanExSv9NlvAZ/f+I/12s8gaZH1GGH14ct/xtd3b+2eVFuhi+pmPwLZtMqZCBwC7UYJTqk1T+XHefza2lFRobpoPrrF5hW2f2v6YHEdC6JbSglokkOV5d5U21/368aW1XVjb7aVddDGXx+Tk/QSc6Xlzq2m8xlLyXkfwWqrtyDxcJdjO1+ik2u4oi7XMc/J5Zo0ia5Swl/VJy/1LrdFy8o+BBOxdMX/vALDHyQ/33Idl534kEzRWGtgSFOdVtZ2tsE0D2xjLe0kV7fU+loD1a+9f228TQrMlOk7EXy6AZG4jTK00sI3K3o5MX2O1zAPbaZOxXHxwdO9nHce8xjZ41ijbzFmj3O6K+ee0UsutIQBsatkSnFdt0lIRGT/w1/X+16X9mL9d2vNuKIvAlh/3jB/Vx+L52i7o/dWU93Lm5PiM2n7s/ZNru7j3by0tsG0prdI2qoh5X/FyWWwV5r6052o7tiyuqFwqsGVLNY8Zz81x5pn1OLG0x3/b78tj0sb5Xzm37tnev7q260sLRWsd2LI+Y42mISzb35lXtkPHNmnks4z8nZzzFlnPfP7bSpvTQ3381doeL4uAn+9O5jn6oxL4cWlzTzBMJS9/47vStrQfK62yl9fKa39W2ufxRGmf50sFAFjWqFQlWOSHdgS7EdgSAkYVJD/yK61GrYa8j9Mn/cgVsAkAS1XUEvhGmEsgebcszt2aB7YEwiFBMGPzCmPW4p3ez+uP95DHT9dtnDO2FhW25SRwHtL743b052uUEJU1GqZh8Ml+O95/KmpjjqnijQpb5j7C2+WlzX2sS9ZwfF8SrMf3KyF3rK0KGwDshBHYEmyO6f3jyiKw5RyxcRViKjl5TM4ti3G7EWzrt5lvKjvzwJbq0AgPCSuZ5wgtCRijepfnpeI2Ats9ZXGBQ+T8sHFBxO4IbLtiGthSJYyxJgm8B/f+oWUR2DL3UflMmB5hNbKu43Gp8o3vV6q1d/e+wAYAy7iztB/pXFEYW0urgJxT2nZWtrfizdJObh9baD+XjXf15aOlVYPuK207LnPLHLMG2fI7oLQKXB5zUX/OjaXNM2EuoS1rc35t1/T7XygtfMT3tT3T+/kvM/Ia+Vs7c77gepHvwou1fd6PPyptjbI2ka3PfA8i/7XKB72f8JW55/uRv/FDH8/cp/PP92sEulwUkb+VNf1q+yMAANihcbHGdBsVAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADacfwCrTdaJvLSVnQAAAABJRU5ErkJggg==>

[image19]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAB8AAAAZCAYAAADJ9/UkAAABVklEQVR4Xu2VvUrFQBCFj4g/hYIoNlbRyhcQLKwE8QVs7SysxTewuZ3vYCvaqohYCDZi4xMELH0IncPM4mRustk0FpIPDtw9k92dmd3kAiMjf8xiNDDtxfFcGHsORJ/R7OJY9B1Ez3PnYm1xzwX0mZkYyJGSOIkBYw35TRMpQXagmC3opKsYMHahz+SYFT2KamgHOC7mC+0t2xDdB6+NQ2iHzqFrDar+Abr5evC5KGM5WOUEmji7xHVYfTGcVEMX8S17tlgOJnjjxtyc1RezDD3zF1HlfHqM5WDCbHeihiYw6Nx52znpyMZL5vXB19F35xq6Du9LMQvQSR82PjMvxzya3wGveIS9pImraJ5jF5VoH3rTkzZFt6InDKw+faXe7HcOVn2J6deT7OC3+mLSraf6bjk/PK/RNFagm7P6QZyautgWvaN5vnsuHv8PKHpFVKaRkf/BD9BfUAs3fN3dAAAAAElFTkSuQmCC>

[image20]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAwCAYAAACsRiaAAAAEwUlEQVR4Xu3c3Yt1UxwH8OX9yUveUigaQriRC3rEUy4ouUHcIEq5UC5EXAi58JKkRBERJUne8lYoIqIkN5IbN3Pnwh/B+tprNdueOTPnOeY8jWc+n/p19lr7zMzea0+db2vtfUoBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIDd44jR9p7R9iHtdby/e2nasUsdOtruYzfum47dseXgG7ubat0w7QQAtt/5tf6a9CWwbRQujivDexM+KOW2sn7sTp60uzfKzh+7U6Ydmzip1qtl/fkDAEuSD90+qxb7aq2M2t1dZXjvndMdu9SRZX1geWTS7p4vO3/sNgrps7zTXldrHT/qBwCWZG+tx0bt90fbYwkd15f1IWU3u7/W1W07AS7tjRxVdv7Y7U9gO729Zsbwz/EOAGB5epDIEulF4x1N+s4uQ/DYyaFjEcfU+nyT2kyWib9r21kiTXuqj+dOH7t5A1sPqF3O6cpJHwCwBPnQTVh7fbqjyT1YuT8r9WPZnnuxvinzhYQby+JB58Sy+M/OK7//6FpfTnc0i47dpbXOmXY2s/qnMvt1xbSzyfLsg6P6dtKe5YtJO8ujq5O+jRyIawEAB7Usia6W9bMncUIZngjsVsoQQrbDPIEtPpt2NIdPOzaQma/N/JcZtkiAyTJyXyYcW+bYzSMhfFZgm5rnWmRZfHy/Y5cglhnErWx1LQCATeSpv3zobvRhnPuyMoM0Np4p+anWE7XuLUOASkj4tAy/68Va59a6pdZZte6u9fXwY//oIeG9WmeU4YGHl1v/47V+bvt7YPulDE8zXtDaT5dhNiizVneU4W/nb0WC0lW1PmntZdlbZs8cbTV2K2U4zpx//FGGBxcy2/VBGQJOzu3ZWg/XeqXW5a3/tPb+m8vaOeYarNR6rrW3O7AlwI5n4Xrlej/Z3vN7287rSq3ba73d9vXAltnGU1t//k+urXVdmX3/JADQLPoEYwJBDwUJVv1D/LyyfkblgVpvliFIRA8J01DR+6eBLaEvoaG3+++J8ZJeAkH/HdNjWIb7ph1z6ueX80i4zTH3gJdzyLHnu86yf/y1G/2cHp20811wCXoJtrHdgW0eOab+9SYJp/2a5KGMfpw9tOZ9CZuzZlABgG2SQNCD0/gpycygPNW2E94yS5SZvHxoX9z6e0jIV4ZEvzdrVmDLklxv31rW/m6O4au2fWYZwsG7rX0gAtui+hOWeTAhM23j0NQDW84tIW789RmzAttqe834XFL2L7DNe2/dVnJMPXT+0F4z83pYWTvOHiizjJz/md9aO/8zAMASZOkr1eUm9B48EqqeKUMYSGjLvn21vq/1YRlmWhIsMkOVZdV+T9pHZbivLvszw5TX18oQAB4qwwMLWRrMclpCYX4uQS2//7IyyP6Eh1QeXNiJcv/cW2Ut2OY8MzaRpeYseWZmLf2pLPdmPNJ/Yeu7prXvKcOSc8YtwSjLp7+Wf1+bAyEhNMe+pwzXJU/R5prloYMcZ44/97ulL9c0cu0+LsPyMgDA/06WExN24oXxDgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgPn8DuRDGOfVyrJUAAAAASUVORK5CYII=>

[image21]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAD8AAAAaCAYAAAAAPoRaAAAC3ElEQVR4Xu2WzatOURTGl4/IV+GGkoQQISZEGCgykFJmwgRloKSkbtKtm2SEFEkZk6+J8lHUTVEGJpKUyVsGBv4I1s/a673rbOd4z6E7UPupp85ee52191p772dvkYKCgoKCgoIa3FE+Uw4rrygvKmdXPAzHlD3lSeUZMf+p0aED9is/Kk8rTylvSv2YjtfK97nxX8GA55XTg+2tWGIR+H1R7kvtBWKF2OwOHUDBviqPpzaxvysP9D2qYG4/ZAKSH1HOz2w7xAZzrFd+UC4Otp1iRVodbG1AjBfKjcFGDApLzBxLlA9kApM/rJwUbHvFVtVxQWzwacEG8nYbHBGLNTezz8zajkvKo9IheRLZrryfeEi5XHlX+Vi5atz1V9UJDHeLTYLztTb4fEr925RjYlv0kVQL1havxGIxLjG+icWcHHwcrPqm9N06+V3Kh+mbCbKlGHSOmJghWBEEJThJfVYurHb3i3Mt9c0TEyjG6Qov5C3lSuUMMc3Jdx+6wI5zW+vkLyunpG+2Jj+SMCvOeUOsIljpq2Lq60U4F/o9+bjNKSS2s8HWBh4rbnvmiu16sHHOt4R26+Tj+RmkyoibX1msKivqBXD4hCMYA9uTzD4IHssXJ9rfpW/mwlUad0Lr5CMQGFa1TpxQ15ikY6vYUVmW2r5VIzz5rhPyM58jFngktOtI/0CQMInHM46w+MPElTeH/+fC+FR+9/PkeRx1AWc9jwWweSHXielJJP0sAt/014KzhCNnZo/Yyq5JfbmIcANw3vOXFSr7Usb92Ak9qfpxXzfdzX/CCrH3QXwzoB/Mk1upCbE4jeDBMiZ2Ld1WvhGbPDihvJG+AcmhsqPKWcHOf/dCm6KhC67ItHmW/s3z1sf0f2kflObnLZqF8JF8T6x4dX59sCWHQhsh2xDaOQjmwpdfORFLxQrICi0Kdv5nvEGMusP/xCEecf9bsAuet2DTjVNQUFBQ0AU/AVVlpzprWb6wAAAAAElFTkSuQmCC>

[image22]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAZCAYAAACB6CjhAAACb0lEQVR4Xu2Xu4sUQRCHy7fIKaIIeoK3GBmIiOChaCpGchdcpGggKoZqIgoiKIiZiXDGRqJoovhADgNBkMtMTcz9I7Q+qoutqd2dvYUVZnA++HHTVXO9012PnhHp6Ojo+M/Zmg0yaMvjTWkcmVXdU63LjqZyUfUnCVvkQ/AN80fOqN6r9mRH0/GNuJIdhd1Sv3Ag+iti8zxMvsZzUOzBn2dH4YTYPXWcVX0Xm+dT8rWC32IPn+uXyH5MtmFQKmzUL7F5NlS8LYCo8eC5fonsWiL6WrWr/GUeNq5VePQeSzV6X4qvDhbr9xwXm4c+0Kos2C7WA76qesGODV8dZAnRB88CsqZ1WcApQPoulfFMsdVBlMma2DtuifUUjsVWsUVsA36UMQvBVseiVN8TojgWp8V9sTmdzapzYTw1/OE9lcfxRHVX7F0hyueZFgdUl8N4p9hvTx2aFw++Wq7H4d0/80oGT4ON0t+gHeGaaPo1r9rMd0ysBFk45cXpNC996E2fxf5nW7CfUl2V8Zk7Ej8N0Ljuz488kMF3B6B82AAapLNP9bPovNgC3qgOBTsLXla9VD0qNhbOffQVYJ53YqV6R3Wy2HuqS6r9qheqvcU+MdeLRsGO53qPeL1GnS4+jkkWBWywfzzdlmom8WJFdB2usTn8Rhz78esQmGdhPBG9on8BtUt5UA7XpP/xxIbHTJp0A/x7hoxwXQj+RnFYLM0XxBrZUxl81yB6sbZHbQB2rvlW+Rb8bPCRMG4UNDeOSBokPSKXELyVaknkDSBjfI4bYtlzUzVX/EfF+kFj8ejy4Dn6a2W92AkSIfLDTqWOjsRfx05/ueyvSLIAAAAASUVORK5CYII=>

[image23]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAZCAYAAACPQVaOAAACTklEQVR4Xu2XzctNURSHf76/IyKZuIlSBkxIUd6JKAMGpgwkmZIUJcVEUiQDUyaUlJGP0DtQSmJgamJm4I9gPdbeWWfd+557k8Eu96lf7zlrnbPv3nt97PNKU6ZMmdIwS7NBw7Z8vyjdRzaZrpjmZUcLnDD9TMIWeRF8o/yRg6bnpvXZ0RJ10aezo7BO/YsEovpWPs715GuKLfJJPsyOwl75M30cMn2Qj/Mq+Zrjh3yiud6I2MtkGwXpzqZ8k4+zoONtDKLBJHO9EbFJIvXUtLb8ZRw2qVlqVG6oG5XZ4uuDhdVndsvHoW6bje4qec2+Mw2CHRu+Pog+UYUaXbKh6ejSjUnB4+V+ZbH1QfTIhljr5+U9gKOoWZbIF/ul3DNpbH0cU/ccjuIoapo60ZqO47htuiw/i6PqOE1DY2GSH8v1OGoXzjzR3F15m+mUfFNgdblGi9M1kF375E0wZhrvHTYdMK0I9ompXRmN68L88DUNn81ACbBYmldkmemmvAnOmmZMZ0yvTZ9Nu0zfTV9N23+/IT0ynTRdND0uNn6T94+a7miyLBzJ2aK5WK7h+oxcTT6037RGHvEasRnTp3INz+Tv7gg2jjL6ArBANpco8g/HoNgZjzn9FYOifw2RYnGXgs4F/x55RGOm8E1+T9132LT7+lMGTULa31X33KZ+K7dMW00P5PUIfJPHLFsoP+44EncG+8Zw3QxE74g8eiyIOoQN8rSG9/IIAs+9MW0u99Q0NhbH+c4GsgEXir856kLnZ0cPLIiPnAw2fFP+S34B6IlvbaNfhowAAAAASUVORK5CYII=>

[image24]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAxCAYAAABnGvUlAAAEy0lEQVR4Xu3c26ttUxwH8OGSW+SWe0pKIXmjQ9RJJA+kSMot5UGScsnlQacQQinJJUmUiDzIA5IUpSQvkhcv582DP4Lxbc5hjzP2WmcvnLOtw+dTv9YcY8yzzppr7prfxphzlQIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP8fv3d11Ny3a0Ffc0Gtc4e+ddB/5lTzw4K+OGRB37p6u9YNte6o9eswFifVurFsHM9ntd6sddefewAAB7yEmreGvkfL5rAW75TN+66Lg2r9NnZWl48d1dXl3w1sp40dS/xS6/yh79uhnWPOsX9SppD2UK37a13S77SF88YOAGC9XF82h5evh3bzUtm87zrJZzu7ay8KnfFprY9qnT4ObJP3xo4FDq/15dhZ7S57zp715+PFWrd17VUl5AEAa253mZYJIwHuhI2hP91dphCRgLCuy20JlD927Q+77d6OWsfV+nwc2CarBLaEr5yL0a6yEdLacu/YTmjLUukHtR4rGzOPOX+7a71a66m5L8us7d/lvQGANZUw1sLBV/1Ap4WbMRTtayeX6T6sZXXNxq6bZMashZcsEz7bjTUJphmL7NuC6nZaJbBlFvCysbPsGdii336tbMyw5d+3GcZX5tcEtxbG+7DavwcAsMbaRbtfUmwuKnvO5qzzBb4tdWaGqgWzXvr741gU6vYmoagFqWv7gb04tEwzXa2+G9qLgllC9BNjZ5nuI+zv1VsW2E6cx1KZTcvDItnu/99mq/O51TgAsE1yUb5u7JyNS4vf1Dpm6NtX/skMW+RJ1swCvjUOzBLomgfKPwsjWVr8O1aZYcvy5c9jZ5k+b3+f2rLAdtP8mvdJwMsS6bJjbf2rfC4A4F+UILPsgv7G0M7yaWaAmlzoz6h1aq0XyvSzEs/U+n4e/3juP7pMs007y3R/1f6S41g0U5i+nV0797Fl3/bwQWav7ijTk5ivl+n+rgSgvD5epocxvijTjFhrt5mq/hi3smowylOit3bthK/xgZBlgS1Lom2GMbOKkeO6ct4+dn6N9h45/jvndmbkEvSyf5vRO7LWWWVaNs9PjWS/K2r9VKZAmO9mlPP9bpn+Fp6e+/L3c/u8fXOZ3ufqMj2xDADsRe53umrsXNHLZQout8zt/KzEpfP2rlrPzeNZQkyQ2N/uGzv+gjxQkc+f8JNQEtlu94MlyCSwpZ3+GI9xK6sGtiYzgfeWKTCt6pQyBbZFD5AsCrP9fvk72FE2gmw7ZwlU/XJqgldmNBP2Fy0/x8Vl+mmVhP52v2CWaJ8v07JttKCW9v6auQWA/70223bh/PpgmWZzchHPhT+zJ5HfFHty3l5XeaAi9+xlGbgFjBbMYgxsaY/HuJV1DyU5b5937RbYstTcy/eTsXxfjwxjTb6fw2odPLczq5mZwjhnfm2BLeFvWfADAPaBRTM5vf430bIc1y7g66Z9zlU+X5b7Us2y3307EB0xdszGc9fCZzv2e8qeDzY8XKaAlu8pD1vE8WUKZi0QJ7C1PgAAtlnuwTuzTKHt/WEscs9fHq5YJSADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/1V/AGV/1KdIfaVdAAAAAElFTkSuQmCC>