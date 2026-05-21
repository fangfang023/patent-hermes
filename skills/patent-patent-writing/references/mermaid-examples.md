# Mermaid 附图绘制示例

本文件提供说明书附图和摘要附图的 Mermaid 代码绘制示例。

## 目录

- [图表类型说明](#图表类型说明)
- [系统架构图](#1-系统架构图)
- [方法流程图](#2-方法流程图)
- [模块交互时序图](#3-模块交互时序图)
- [绘制要点](#绘制要点)

---

## 图表类型说明

| 图表类型 | Mermaid 语法 | 适用场景 |
|---------|------------|---------|
| 系统架构图 | `graph TD` | 展示系统各层级模块及连接关系 |
| 方法流程图 | `flowchart TB` | 展示技术实现步骤流程 |
| 模块交互图 | `sequenceDiagram` | 展示各模块交互的时序关系 |

---

## 1. 系统架构图

### 基本语法

```mermaid
graph TD
    A[模块A] -->|连接说明| B[模块B]
    B --> C[模块C]
    C --> D[模块D]
```

### 完整示例

```mermaid
graph TD
    A[终端设备层<br/>数据采集模块<br/>采集：点击流/心率/鼠标轨迹] -->|5G传输<br/>AES-256加密| B[数据传输层<br/>加密模块<br/>保障数据安全]
    B -->|HTTPS协议<br/>TLS 1.3| C[云端处理层<br/>数据融合模块<br/>D-S证据理论融合]

    style A fill:#e1f5ff
    style B fill:#fff4e1
    style C fill:#ffe1f5
```

### 层次化架构图

```mermaid
graph TB
    subgraph 终端设备层
        A1[数据采集模块]
        A2[缓存模块]
    end

    subgraph 数据传输层
        B1[加密模块]
        B2[传输模块]
    end

    subgraph 云端处理层
        C1[数据预处理单元]
        C2[数据融合单元]
        C3[评估单元]
    end

    subgraph 数据存储层
        D1[关系型数据库]
        D2[时序数据库]
    end

    A1 --> B1
    A2 --> B2
    B1 --> C1
    B2 --> C1
    C1 --> C2
    C2 --> C3
    C3 --> D1
    C3 --> D2
```

---

## 2. 方法流程图

### 基本语法

```mermaid
flowchart TB
    S1[步骤1] --> S2[步骤2]
    S2 --> S3[步骤3]
    S3 --> S4[步骤4]
```

### 完整示例

```mermaid
flowchart TB
    S1[步骤1：数据采集<br/>每1秒采集心率数据<br/>采样频率1Hz] --> S2[步骤2：数据预处理<br/>去除异常值<br/>3σ原则]
    S2 --> S3[步骤3：特征提取<br/>提取时域/频域特征<br/>小波变换]
    S3 --> S4[步骤4：数据融合<br/>D-S证据理论<br/>冲突阈值0.8]
    S4 --> S5[步骤5：动机评估<br/>LSTM模型输出评分<br/>时间步长10]

    style S1 fill:#e3f2fd
    style S2 fill:#e3f2fd
    style S3 fill:#fff3e0
    style S4 fill:#fff3e0
    style S5 fill:#f3e5f5
```

### 带条件判断的流程图

```mermaid
flowchart TB
    Start[开始] --> Collect[数据采集]
    Collect --> Check{数据质量检查}
    Check -->|合格| Preprocess[数据预处理]
    Check -->|不合格| Discard[丢弃异常数据]
    Discard --> Collect
    Preprocess --> Extract[特征提取]
    Extract --> Fuse[数据融合]
    Fuse --> Evaluate[动机评估]
    Evaluate --> Output[输出结果]
    Output --> End[结束]

    style Start fill:#e8f5e9
    style End fill:#e8f5e9
    style Check fill:#fff9c4
    style Discard fill:#ffcdd2
```

---

## 3. 模块交互时序图

### 基本语法

```mermaid
sequenceDiagram
    participant A as 模块A
    participant B as 模块B
    participant C as 模块C

    A->>B: 发送请求
    B->>C: 处理数据
    C-->>B: 返回结果
    B-->>A: 返回响应
```

### 完整示例

```mermaid
sequenceDiagram
    participant U as 用户
    participant C as 客户端
    participant S as 服务器
    participant D as 数据库

    U->>C: 打开学习课件
    C->>C: 启动数据采集线程
    C->>S: 上传采集数据<br/>(JSON格式，AES加密)
    S->>S: 数据融合处理<br/>(D-S证据理论)
    S->>S: 动机评估计算<br/>(LSTM推理)
    S->>D: 存储评估结果<br/>(MongoDB)
    S-->>C: 返回评估报告<br/>(RESTful API)
    C-->>U: 展示评估结果<br/>(仪表盘)

    Note over S: 核心处理耗时<br/>< 2秒
```

### 复杂交互场景

```mermaid
sequenceDiagram
    participant U as 用户
    participant C as 客户端
    participant S as 服务器
    participant F as 融合模块
    participant E as 评估模块
    participant D as 数据库

    U->>C: 登录系统
    C->>S: 验证用户身份
    S-->>C: 返回用户信息

    U->>C: 开始学习课件
    C->>S: 创建学习会话
    S->>D: 保存会话ID

    par 并行数据采集
        C->>C: 采集点击流数据
        C->>C: 采集生理数据
    end

    C->>S: 上传采集数据
    S->>F: 请求数据融合
    F->>F: 时间对齐<br/>(滑动窗口10s)
    F->>F: 特征提取<br/>(时域+频域)
    F-->>S: 返回融合特征

    S->>E: 请求动机评估
    E->>E: LSTM推理<br/>(时间步长10)
    E-->>S: 返回评分

    S->>D: 保存评估结果
    S-->>C: 推送实时评分
    C-->>U: 更新仪表盘

    Note over S,E: 评估周期<br/>5分钟/次
```

---

## 绘制要点

### 1. 模块/节点命名要求

**错误示例**（仅包含模块名称）：
```
A[数据采集模块]
B[数据融合模块]
```

**正确示例**（包含功能描述）：
```
A[数据采集模块<br/>采集点击流和心率数据<br/>采样频率1Hz]
B[数据融合模块<br/>采用D-S证据理论<br/>融合多源数据]
```

### 2. 连接关系标注

每条连接线应标注数据/信息类型：
```
A -->|JSON格式数据| B
A -->|AES-256加密| B
A -->|HTTPS协议| B
```

### 3. 颜色和样式

使用颜色区分不同类型的模块或步骤：
- 蓝色：输入/前端模块
- 黄色：处理/核心模块
- 紫色：输出/后端模块
- 绿色：开始/结束节点
- 红色：异常/警告节点

### 4. 图表简洁性

- 避免在单幅图表中展示过多信息
- 核心信息应一目了然
- 详细信息通过标注体现
