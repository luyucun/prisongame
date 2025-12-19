策划文档

概述：
1.这是一款基于roblox的游戏，玩家通过在商店购买兵种，然后合成兵种后，获得更强力的兵，并且通过获得的兵种去战斗，以获得更多的金币

大概的玩法是：玩家在商店购买兵种，通过兵种合成，将兵种放在地上，让地上的兵种自动去挑战关卡，然后玩家获得更多的金币
在开发的过程中要考虑好整体架构
游戏大概一个服务器6名玩家，每个玩家根据服务器分配出现在对应的出生点上
在出生点上出生后，要加载玩家的货币数据以及已经拥有的兵种的数据，在场地上生成对应的内容，这部分下面会详细讲解

接下来我们将有序按照版本顺序进行开发，最终实现该游戏的开发

V1.0版本

货币系统定义：
1.我们在游戏中定义一种货币：金币
2.金币可以通过各种渠道来获得，比如战斗/挂机/付费购买等，这些我们在后面的开发过程中会逐步补充，当前版本只需要完成金币的定义
3.玩家的初始金币数量为100

关于金币数量的显示
StarterGui - MainGui - CoinNum是一个Textlabel，用于显示玩家的金币数量
玩家金币数量显示需要实时更新，每当玩家的金币数发生变化的时候都需要进行更新
金币的显示格式为：$XXXXX ，其中XXXXX为玩家的当前的金币数量

在开发过程中，要为以后的金币数量获得预留好接口设计好架构，获得金币的渠道有：
1.玩家通过主线关卡挑战来获得金币
2.玩家通过挂机机制来获得金币
3.玩家通过购买开发者产品来获得金币

玩家基地定义：

在我们的游戏中，设定每个服务器最多6名玩家
每个玩家在游戏中都有属于自己的基地，在玩家进入游戏后，系统随机将玩家分配到游戏内的6个基地之一作为玩家的基地并加载玩家的数据

在游戏中，workspace下，有个文件夹叫Home，是所有玩家的整体信息的总文件夹，其下有PlayerHome1到PlayerHome2共6个文件夹，分别用于承载6个玩家的基地信息
下面以PlayerHome1为例子进行举例：
    PlayerHome1下有个SpawnLocation，如果玩家进来时系统将其分配为了1号玩家，则该玩家就出生在PlayerHome1下的SpawnLocation

    目前先实现到这个级别，其他功能我们后续慢慢开发即可

    注意：玩家的位置分配是从1到6的空位中随机一个，而不是按顺序固定1到6排序


V1.1
兵种定义与实现：

兵种类型
兵种攻击方式

我们在游戏中定义多种类型的兵种，作为我们游戏中的“战斗角色”

兵种最基础分类为：近战单位和远程单位
我们会有各种包装类型的兵种，但是本质上就是近战单位与远程单位的区别

士兵有等级区分，从1级到6级
每个兵种都有属于自己的模型，兵种模型放在ReplicatedStorage中，我会给每个兵种配置对应的模型路径，代码需要支持根据我配置的路径去寻找模型
每当我购买获得通过其他方式获得了一个兵种，就从路径下复制一个模型作为表现，然后根据数据生成一个兵

每个兵种可以通过商店来进行购买，购买时需要花费玩家的金币，购买成功时会获得该兵种的1个基础1级兵
每个兵种根据体型大小，会有占地格子数的区分，有些兵种只占据1个格子，有些兵种会占据4个格子

下面我们举个例子：
兵种1：
    名字：Noob
    模型路径：ReplicatedStorage/Role/Basic/Noob
    类型：近战
    基础等级：1级
    购买价格：100（这里指金币）
    占地面积：1格

兵种2：
    Rookie
    类型：近战
    模型路径：ReplicatedStorage/Role/Basic/Rookie
    基础等级：1级
    购买价格：200（这里指金币）
    占地面积：1格


我们需要一张专门的士兵表，用来配置士兵类型，支持我拓展不同的兵种

其实购买兵种时，就是获得一个对应的兵种，玩家可以同时有多个相同的兵种，比如有3个Noob，2个Rookie等

关于兵种的获得：

1.这个版本我们暂时不开发兵种的购买功能，我们通过命令行工具用gm命令来测试兵种的获得
2.兵种购买完成后，需要暂时先放在我们的背包中（暂定放在背包中即可），其实可以理解为兵种就是一个商品道具，兵种放在背包中暂定就用名字显示在背包里即可


V1.2 兵种放置

基本功能描述：每个玩家都有一块基础地板，玩家可以将背包中的兵种放在地板上，但是也只能放在地板上，不能放在其他地方

放置地板定义：

每个玩家的家园中都有一个叫IdleFloor的Part，是用来放置兵种的地板，兵种只可以放在该Part上
以PlayerHome1举例，IdleFloor的路径是Workspace - Home - PlayerHome1 - IdleFloor
IdleFloor是由14*14个基础大小的studs组成的，我们在配置表中说的兵种的占地面积就是指占据多少个studs，占据1格就是1*1studs，占地4格就是2*2studs，占地9格就是3*3studs
IdleFloor的大小是标准的120, 1, 120，做摆放范围限制时可以用studs大小限制也可以获取IdleFloor的中心坐标，然后根据大小来做范围限制

地板格子定义：
1.每个studs是一个基础放置单位，每个模型只能占据1或者4或者9个studs
2.模型放下去后，就以studs的中心做为模型HumanoidRootPart的放置点，总之就是把模型放在所属格子的中心


放置流程：
1.选中兵种
2.在地板上出现兵种（此时还可移动，并未真正放下），此时可定义为：放置中
3.放置完成，从背包扣除该兵种数量，并真正放置在地板上，视为放置完成。

选中兵种：
主要是通过点击背包中的兵种信息来完成选中
这里有一点要注意：我们现在的背包中的兵种看起来不支持点击，这里要改成能点击能选中

放置操作（电脑端）：
1.玩家点击背包中的兵种，触发摆放操作
2.在鼠标处出现选中的兵种的模型，出现时有几个表现需要特殊实现：
    a.出现的兵种需要有高光，具体逻辑是：每个兵种模型下都有一个Highlight，高光就是把Highlight的颜色改成0, 255, 0，把Highlight的filltransparency改成0.4
3.玩家点击鼠标左边，触发确认操作，此时彻底把模型放在所属的地板上，放置完成；但是如果玩家点击鼠标左键，则视为取消放置，从鼠标端移除模型，结束本次放置操作


放置操作（移动端）
1.玩家点击背包中的兵种，触发摆放操作
2.在玩家当前角色朝向前3studs的位置，出现兵种的模型，进入放置中的状态
3.玩家可通过手指拖动模型来确定要摆放模型的位置
4.在模型放置过程中，需要显示出ui：将StarterGui - PutConfirm的Enable属性改成True
5.玩家点击tarterGui - PutConfirm - ButtonBg - Confirm按钮，视为确认放置，将模型成功放置在地上，并且结束放置流程，并隐藏ui：将StarterGui - PutConfirm的Enable属性改成false
6.玩家点击tarterGui - PutConfirm - ButtonBg - Cancel按钮，视为取消放置，将模型移除，并结束放置流程，并隐藏ui：将StarterGui - PutConfirm的Enable属性改成false


放置范围：
我们设定兵种只能放在IdleFloor上，不能超出放置范围，以及在放置阶段鼠标就算移出IdleFloor范围，兵种也不能跟着移出去，最多到IdleFloor边上，移动时贴着IdleFloor的边移动，类似空气墙撞墙那种效果


吸地的逻辑：
由于我们的兵种占地格子是标准的studs，而不是随便摆放，所以我们的兵种在放置阶段的时候，拖动鼠标或者手指拖动位置时需要有吸附效果
具体的吸附逻辑是：
    1.玩家在移动兵种过程中，如果松手时，兵种没有放在正好的占地studs中心，则需要把模型强制移动到模型中心放下，看起来是被吸附到了位置上
    2.在用鼠标或者手指移动的过程中，不要做成实时模型跟着移动，要去判断鼠标或手指的位置，看鼠标或者手指的位置离哪个studs中心近，如果还是离当前的studs单位更近，模型保持不动，如果鼠标移动到离边上的studs更近，则要立刻把模型吸附过去
    3.鼠标或手指移动的过程中，看起来就是模型一顿一顿被吸附着移动的，而不是自然而然流畅的线性移动


功能修改：
我修改下我在策划案中关于studs的表述，我的表述是有问题的，我的一个兵种占据
  的格子其实是由一个4*4的studs组成的，也就是16个studs组成的正方形，2*2的格子其实是8*8的共64个Studs组成的，3*3的格子其
  实是12*12共144个Studs组成的

V1.2.1
补充关于兵种放置相关的需求：

放置表现修改：
1.放置兵种时，将现在HighLight的修改FillColor的颜色改为修改OutlineColor的颜色，色号不变依然是0, 255, 0，也就是我们不改FillColor的颜色了，变成改OutlineColor的颜色
2.去除现在的HighLight的修改FillTransparency的逻辑，保持默认值即可
3.放置结束后，取消HighLight的效果

放置表现补充：
1.放置过程中，需要在兵种当前脚底的格子上，盖一层Part
2.根据模型当前的吸附效果所属的格子，从Workspace - Grid中去复制一个对应的Part盖在格子上
3.占地1*1的模型，去复制Workspace - Grid - GridGreen1，占地2*2的模型，去复制Workspace - Grid - GridGreen2，占地3*3的模型，去复制Workspace - Grid - GridGreen2，占地3
4.复制出来的Grid的Part需要根据模型的位置实时变化，模型到哪里，Grid下的Part就跟着移动到哪里
5.当放置完成后，再移除复制出来的Grid的Part
6.其实就是给模型脚底放一个用来凸显位置的发光小块

位置冲突：
1.放置模型时，我们现有的逻辑是：同一个格子上无法放置两个模型，这个逻辑没错，我们现在要加入相关的表现
2.在放置过程中，如果模型当前的位置与其他已经放置了模型的位置重叠了，那走跟上面一样的表现逻辑，也是去Grid下复制模型，只不过复制的分别是GridRed1/GridRed2/GridRed3
3.这两种应该是实时切换的，我当前的位置支持放下去，就是绿色的Grid，如果发现位置冲突无法放下，就需要把绿色的Grid换成红色的Grid,然后我又挪开后发现又支持放下去了，就再改成绿色的Grid


V1.3 兵种回收

我们在基地上放下的兵种，支持再收回背包中

具体逻辑是:
1.玩家点击StarterGui - MainGui - Remove这个按钮，触发回收流程：
2.回收流程下：需要：
    a.自动将背包按钮切换为显示状态，同时将MainGui - Start的visible属性改成false，将MainGui - CoinNum的visible属性也改成False
    b.将StarterGui - MainGui-RemoveTips的Visible属性改成True
    c.将StarterGui - MainGui - Remove的Visible属性改成false
    d.将StarterGui - MainGui - Exit的Visible属性改成True

3.玩家点击Exit按钮，或者当场中没有任何一个摆放中的兵种模型时，退出回收流程，退出回收流程后：
    a.将StarterGui - MainGui - Exit的Visible属性改成false
    b.将StarterGui - MainGui-RemoveTips的Visible属性改成false
    c.将StarterGui - MainGui - Remove的Visible属性改成true
    d.自动将背包按钮切换为隐藏状态，同时将MainGui - Start的visible属性改成true，将MainGui - CoinNum的visible属性也改成true

回收操作：
在回收流程中时，玩家点击场中已经摆放的模型，可以将该模型从场中移除，释放出占据的位置，并将该模型收回到自己的背包中
回收状态下点击模型时，需要将模型的HighLight的描边改成红色

注意：在回收状态下，点击背包中的兵种信息，无法触发摆放操作，一定要退出回收模式，才能点击背包中的兵种信息触发摆放操作


V1.4 兵种属性设定

我们给兵种定义集中属性：
基础攻击力：决定基础伤害
基础生命值：决定基础的存活能力
基础攻击速度：决定每完成一次普攻需要的时间

另外我们会定义兵种等级：兵种基础等级为1级，可以提升兵种等级，最高等级为3级

兵种的生命值与攻击力会随着等级提升而提升，在等级提升后，数值会有相应的提升
具体计算逻辑是：
兵种属性=1级时属性*等级*等级系数

1级的等级系数是1，二级的等级系数是1.2，3级的等级系数是1.5
也就是比如1级攻击力是100，2级就是100*2*1.2=240，3级就是100*3*1.5=450

兵种等级显示：
在每个兵种的模型下，有个Head模型，其下有个叫BillboardGui的BillboardGui，其下有个叫TextLabel用于显示兵种当前的等级，格式是：Lv.X，注意：如果达到了最高级，这里显示的是Lv.Max

兵种升级：
两个相同等级的同UnitId兵种，可以合成成一个更高等级的同UnitId兵种
比如两个1级Rookie，可以合成一个2级的Rookie

合成兵种等级有上限限制，最高等级到3级，3级就无法再合成

合成操作：
玩家直接拖动场上的兵种，拖动到另一个同等级同UnitId的兵种的位置，保持位置重叠，松手（或者送鼠标）后，进行合成判断

合成预览：
1.如果两个兵种满足合成条件，则在把A拖动到B时，在B的位置复制Grid下的GridGreen1或者GridGreen2或者GridGreen3，这一块的逻辑参考摆放兵种时的兵种脚底的GridGreen或GridRed的Part的显示逻辑即可
2.如果不满足合成条件，则A拖动到B的时候，在B脚底显示的是红色的GridRed


如果满足合成条件，则：
    1.移除原来的两个基础兵种
    2.在当前位置生成一个更高一级的同UnitId的兵种

如果不满足合成条件，则：
    1.系统飘字提示：无法合成
    2.将拖过来的兵种，移动回拖动前的位置

V1.4.1补充需求：

1.在玩家拖动兵种模型的时候，我需要把兵种模型的高度稍微抬高一点，看起来是被拔起来了，这个参数我希望可以我自己调整
2.在合成新的兵种或者回归原位时，再恢复原来的高度

3.在玩家拖动的过程中，我希望把兵种的HighLight的描边改成绿色，在放下或者回归原位时再恢复为默认状态
4.如果把A放在B身上，二者不符合合成条件时，不光要在B脚底出现Grid的红色GridRed，也要把A的HighLight描边改成红色

我们这里补充一下关于默认状态下的HighLight的描边的状态：
默认状态下，也就是模型被放在地上的状态，模型的描边应该是透明度为1，在拖动时或者摆放时，才把描边的透明度改成0，只要放在地上完成了，就该把描边透明度改为1


另外我需要补充一个逻辑：
我们现在拖动模型到一个空位的时候，是无法完成换位置的，但是我希望这个效果是可以实现的
也就是我可以把A拖动放到一个空位处

所以这里我们的拖动时候的需求就统一变成：
1.只要拖动，就把模型抬高，并且脚底有出现绿色的Grid的Part，同时角色身上有绿色描边
2.如果是拖动换位置，那和我们摆放模型时的流程是一样的，就当重新进入了摆放模型的流程
3.如果是合成，拖动到目标兵种上后，还是要保持我们的如果不满足合成条件脚底就是红色并且身上是红色HighLight描边，松手后回原位

再次补充：我们移除了拖动时抬高角色的机制，改为不抬高

V1.5 战斗系统构建

战斗系统构建：
概述：
我们将会构建一套基础的战斗系统，我们的战斗是由玩家的小兵与关卡中的小兵之间根据AI逻辑自动进行战斗，而不是玩家之间互相战斗

战斗基础部分：

基础属性定义：
在我们之前的玩家属性定义部分已经增加了相关的定义，这里再次说明，我们的兵种共分4类基础属性：
攻击力：决定了在战斗时会对敌方造成多少伤害
血量：决定了兵种的生存能力
攻击速度，决定了在战斗时，兵种多久进行一次基础的普通攻击
攻击距离：决定了兵种离目标多远时开始发动普攻
移动速度：决定了兵种在场上的奔跑速度
以上属性都要在兵种的配置表中体现出来，由字段进行控制

伤害公式：造成的伤害值=攻击方的基础攻击力
比如某个兵种基础攻击力是100，那么攻击了敌方1次后，将会扣除敌方100点血量

伤害流程：
1.如果是近战，需要判定角色的手中的攻击武器是否与目标的身体完成了接触，如果完成了接触，视为攻击生效，则走伤害公式计算出本次伤害，然后给敌方扣除对应的血量
2.如果是远程，需要判定角色发射出的子弹弹道是否与敌方身体完成了接触，如果完成了接触，则视为攻击生效，则走伤害公式计算出本次伤害，然后给敌方扣除对应的血量
3.不论是近战还是远程，都是在武器或者弹道与敌方身体发生接触的时候进行扣血

死亡流程：
当兵种的血量小于等于0时，兵种立刻死亡：播放死亡动作，并在战斗场景中消失

攻击目标寻找：
1.战斗开始后，攻击角色需要立刻寻找一圈场上的敌方单位，锁定一个直线距离离自己最近的敌方单位，开始朝目标移动，移动时根据自己的移动速度进行移动
2.在移动过程中，当角色判定攻击目标与自己之间的直线距离小于自己的攻击距离时，就立刻停下来移动，开始对目标进行普通攻击
3.在每次攻击之前，都需要判定一次目标与自己之间的距离，如果双方距离大于攻击距离，则要继续移动到目标身边直至进入自己的攻击距离内，才能停下来进行普通攻击
4.在每次普攻之前，也需要进行另一层的判断，就是对方是否已经死亡，如果判定敌方已经死亡，则去继续寻找下一个距离自己最近的目标，并开始朝目标移动并在符合条件的情况下进行普通攻击
5.也就是流程是寻找目标→确定目标→判定双方距离是否在攻击范围内→如果不是就朝目标移动/如果是就开始普攻
6.关于敌方死亡的判断，需要在目标死亡的瞬间发送通知给攻击方，这样攻击方可以收到信号停止进攻并开始寻找新的攻击目标
7.如果场中已经没有可以寻找到的攻击单位，则进入待机流程
8.如果在朝目标移动过程中遇到了障碍物，则要始终持续保持寻路，直至对方死亡切换目标或彻底找不到新的攻击目标
9.兵种移动就播放角色身上默认的移动动画即可

普攻流程：
（这里讲的是已经进入攻击范围内后符合攻击条件下已经触发普通攻击时的攻击流程）
1.近战：原地站定，并播放普通攻击动画，普通攻击动画id需要在兵种表中进行配置；
2.远程：原地站定，并播放普通攻击动画，普通攻击动画id需要在兵种表中进行配置
注意，远程单位攻击时，需要从自己的武器中发射出子弹，子弹需要飞向目标，远程单位的弹道飞行速度在兵种表中需要添加一个配置来控制。近战单位的这个属性填0即可，远程单位的这个值填的数值，代表发射出来的子弹在场中的飞行距离。并且有个重要的点是：远程单位发射出来的子弹不与非目标进行碰撞，只与目标进行碰撞，理论上子弹可以穿过所有的非目标单位的身体。
远程单位的弹道是始终追踪目标单位的，举个极端点的例子，目标单位在场中做S型移动，那么弹道也会始终朝他的位置移动，也就是只要没追到目标，就会始终朝目标移动，类似跟踪炮弹一样

基础战斗测试模块需求：
我需要在游戏中对我们的战斗系统进行测试调试，所以需要一套简易的战斗系统调试工具，具体需求是：
我在游戏中的Workspace下新建了一个文件夹，叫做：BattleTest，这个文件夹下有两个子文件夹叫Attack以及Defense。Attack下有5个Part，分别是Position1到Position5，在Defense下也有5个Part，分别是Position1到Position5。以上的两个文件夹是用来在测试战斗的时候攻击方的兵种生成位置以及防守方的兵种生成位置，每个Position都有坐标信息，生成时直接获取PositionX的坐标信息在对应坐标处生成兵种即可

兵种的碰撞：
兵种之间是需要有碰撞的，敌方兵种与我方兵种及我方兵种和我方兵种之间都需要有碰撞

需要创建一套简易的UI，用来生成对战的兵种，里面大概的信息有：
1.进攻方/还是防守方的选择列表
2.可用的兵种列表（配置表中有的兵种都算进来）
3.生成的位置（position1到Position5可选）
4.生成的等级，也是下来列表，最多从1级到3级可选
以上四个都是下拉式列表，三个选择完的信息共同组成一个兵种的生成信息，包括位置、兵种、等级、攻击方还是防守方

然后在简易UI上，有个开始按钮，点击开始后，兵种开始进行战斗。在战斗过程中，直至有一方全部死亡完后，战斗结束，并且等待3秒后，将场中生成的测试兵种移除

简易UI需要有个快捷打开与关闭的方式，使用键盘V键，打开简易战斗调试UI

注意我们的战斗逻辑：一个服务器有多个玩家，每个玩家都有自己的兵种，每个玩家都可以让自己的兵种去进行战斗。所以极限情况下多个玩家都在同时进行自己的战斗
我们的服务器最多同时承载8个玩家

补充一些当前字段的说明：
 WeaponName 字段的作用

  定义

  WeaponName = string  -- 武器名称(模型中的Tool或Part名称)

  具体用途

  WeaponName用来定位兵种模型中的武器Part/Tool的名称，以便：

  1. 获取子弹发射起点
    - 远程单位发射子弹时，需要从武器位置而不是身体中心发射
    - 查找模型中与WeaponName相同名称的Part
    - 从该Part的位置发射子弹
  2. 工作流程（在ProjectileSystem中）

  关于枪口发射逻辑：

  实现方式：

  1. 模型结构：
  Archer (Model)
  ├── HumanoidRootPart
  ├── Head
  ├── Torso
  └── Rifle (Model 或 Part)  <-- WeaponName = "Rifle"
      ├── RifleBody (Part)
      ├── RifleBarrel (Part)
      └── MuzzlePoint (Part)  <-- 专门的发射点，位于枪口位置

子弹配置方式

  自定义模型（最灵活）

  步骤1：在ReplicatedStorage中创建模型
  ReplicatedStorage
  └── Projectiles (Folder)
      ├── Arrow (Model) - 箭矢模型
      │   ├── ArrowHead (Part)
      │   ├── ArrowShaft (Part)
      │   └── ArrowFeathers (Part)
      ├── Fireball (Model) - 火球模型
      └── Stone (Part) - 简单石头

 步骤2：在UnitConfig中配置
  ["Archer"] = {
      UnitId = "Archer",
      Type = UnitConfig.UnitType.RANGED,
      WeaponName = "Bow",
      ProjectileSpeed = 80,
      ProjectileModelPath = "Projectiles/Arrow",  -- 指向模型路径
      -- ...其他配置


V1.5.1补充修改

关于近战逻辑的一些调整优化：

1.不要完全依赖 Touched
    Touched 在多人/高并发场景下不稳定（重复触发、漏触发、靠物理帧），且容易被客户端篡改或被网络延迟影响。更适合用于物理交互而非判定伤害的最终来源。
2.推荐：动作标记（Animation Marker） + 服务端判定（距离/射线/重叠）
    在攻击动画里放一个 Hit 标记（Animation Event / AnimationTrack:GetMarkerReachedSignal），当标记触发时由服务器计算是否命中：
    检查目标是否仍存活；
    检查距离（<= 攻击距离 + 宽容值）；
    可选：射线检测（Raycast）或形状重叠（Overlap）用于判断是否有遮挡或目标在朝向范围内。
3.大致思路：
    动画时刻 + 距离+射线（推荐）：简单、稳健、对性能友好。
4.服务端权威
    所有判定都要在服务器做，客户端仅用于播放动画/特效。避免客户端直接调用 TakeDamage。
5.死亡通知与目标切换
    建议维护一个 UnitManager（或把所有活着的单位存在一个表里），当单位死亡时触发通知（事件/回调），攻击该单位的所有人会收到信号并重新 FindTarget()。
6.性能与并发注意
    AI 搜索频率不要过高（比如每 0.2–0.5 秒一次查找/更新目标）
    对场上单位做分组（按玩家/阵营）以减少不必要的遍历
    使用 Overlap 查询时，尽量用小频率/短时间窗来减少压力


V1.5.2补充 
补充关于兵种动作逻辑的一些说明

我们的每个兵种有5个动作：
show：在IdleFloor上摆放着的时候，需要循环不断播放的动作
idle：在战斗中，两次普攻之间的动作，开始站定是idle动作，然后普攻播attack，然后恢复idle,下次攻击再attack，再恢复
attack：普通攻击动作，每次普通攻击需要播放的动作，也就是我们的攻击动作
run：移动时候的动作
die：兵种死亡时播放的动作

以上五个动作，每个兵种都需要单独进行配置

如果没有配置，则使用角色默认动画或者无动画即可

V1.5.3
在我的游戏中，有兵种合成功能，也就是两个相同id相同等级的兵种可以合成一个更高级兵种

现在我们需要给兵种合成的时候添加合成特效，具体的逻辑是这样的：

1.在我们的游戏中，兵种大小分1*1/2*2/3*3共3种占地大小
2.在我们的游戏中，ReplicatedStorage - Effect这个文件夹下放着3个特效，分别是Merge01/Merge02/Merge03，分别对应1*1大小的单位/2*2大小的单位/3*3大小的单位
3.在合成的一瞬间，需要根据兵种的占地大小类型，去ReplicatedStorage - Effect下复制对应的特效，在兵种合成的位置处生成一份
4.特效播放时间为0.3秒，0.3秒后移除
5.以Merge01举例，这是一个透明Part，下面有各种特效信息，可以直接把Merge01复制过去。0.3秒后移除即可


V1.5.4关于远程武器特效播放

现在我们来处理远程单位战斗相关的逻辑：现在每个远程单位都有自己的weapon，然后在每个武器的节点下，都有一个叫Effect的Part，其下挂载着我们的远程武器发射时相关的一些特效内容：

Effect下有个叫Beam的Beam，在子弹发射的瞬间（也就是动作到attack的时候），需要立刻把Beam的Enable属性改成True，然后等待0.1秒后再改成False
每次攻击时，都重复执行一次，也就是每次攻击，都把beam快速显示出来一次

Effect下有个叫PointLight的PointLight，和Beam一样的逻辑，发射时把Enable属性改成True后0.1秒后再改成False

Effect下有多个粒子，名字从ParticleEmitter01到ParticleEmitter02或者ParticleEmitter03，数量不确定，所以你需要用脚本去遍历这把枪下面有多少个粒子
每次发射时，把这把枪下的所有粒子的Enable属性都改成True，然后等待0.5秒后，把所有粒子的Enable属性改成False

这里要有个点注意一下：当武器发射的很快时，如果一次攻击后，0.5秒内粒子还没有被改成Enable=false的情况下，再次进行攻击了（攻速很快），需要立刻跳过0.5秒的限制，立刻把粒子的Enable改成False，然后重新执行发射逻辑，也就是再次把粒子的Enable属性改成True，也就是强行关掉再开一次，保证每次开枪都是重新开始播了一次粒子



V2.0   挑战关卡相关

在我们的游戏中，是有挑战关卡相关的这个概念的，具体逻辑概述下就是：
玩家在基地点击开始攻击，基地放置的兵种会自动往前移动朝关卡目标点移动，到了位置后开始攻击关卡内敌人，打完后自动移动到下一关，循环往复，当己方单位全死完后结束战斗，全部兵种恢复到原地

军队概念：
每个玩家家园中的idleFloor是用来摆放和合成兵种的，玩家当前摆放出来的兵种就算是玩家的军队
玩家摆放出来的每个兵种都有自己的等级信息/以及对应的攻击力生命值等各类属性，本质上是一个小兵单位

关卡挑战：
玩家可以点击游戏中的开始挑战按钮，让自己的军队开始进行挑战
军队需要一直不断自己寻路向前，去挑战关卡，打完了第一关，就继续自动寻路去寻找第二关，打完第二关继续去寻找第三关，直到打完全部关卡或者全部死亡
在挑战过程中，兵种的血量是继承的，比如A兵打完了第一关还剩50%血量，那么在打第二关的时候就是以剩余的50%血量去继续战斗的

开始战斗后的状态：
开始战斗后，自己基地的小兵就都开始往关卡中走了，也就是从关卡中消失了，在这个过程中，无法再往基地地上摆放兵种

结束战斗状态：
所有兵种重生在基地的IdleFloor上，并且重生时，要播一遍兵种对应大小的合成特效

以上都是基础的概念设定，下面是具体详细的规则说明：

开始战斗:
1.玩家点击StarterGui - MainGui - BattleControl - Play按钮，可以开始战斗流程
2.在进入战斗流程后，将StarterGui - MainGui - BattleControl - Play的Visible属性改成False
3.在进入战斗流程后，将StarterGui - MainGui - BattleControl - Retreat的Visible属性改成True
4.在结束战斗流程后，将StarterGui - MainGui - BattleControl - Play的Visible属性改成True，将StarterGui - MainGui - BattleControl - Retreat的Visible属性改成False

兵种坐标：
我们的兵种摆放在IdleFloor上的，每个兵种占据住一个或者几个格子后，理论上能得出一个这个兵种在这个格子上的详细坐标，比如（3，6），代表第3排第6列的这个格子信息
当战斗结束后，兵种需要在基地重新出现的时候，就根据该兵种之前记录的在格子上的坐标，在对应位置刷出该兵种
兵种只有在非关卡挑战中状态下才能摆放/挪动/合成/回收操作：

关卡地图：

一个服务器最多有6个玩家，每个玩家都有自己的基地，都有自己的兵种
每个玩家的关卡挑战都是自己独立的

我们以PlayerHome1来进行举例，也就是出生在1号位的玩家：
在PlayerHome1下有个文件夹叫做Stage，主要用来放置关卡场景，以及关卡里面的基础信息
Stage下只有第一关的关卡场景是固定存在，后面的关卡都由程序动态加载生成，打完了就移除

玩家挑战的时候都是从第一关开始挑战的，第一关也就是Workspace - Home - PlayerHome1 - Stage - Stage001
在挑战当前关卡的时候，就需要动态加载出下一关的场景，具体的加载规则是：
1.在ReplicatedStorage - StageTemplate - Style01下放着关卡场景模板，其中有两个文件夹，其中一个叫StageMiddle，里面放的是战斗中段的场景，另一个文件夹是StageEnd，放置的是最后一关的场景
2.当挑战关卡时，需要在当前关卡后方生成下一关的场景，如果已经是最后一关，就不再生成
3.比如我们共10关，当前在打第一关，那么在战斗开始后就需要在第一关后面把第二关的场景生成出来，当进入第二关的场景中时，需要把第三关的场景复制出来，但是如果当前正在打第十关，那么就不再复制了
4.如果关卡是中间段的关卡，比如共10关的话，2到9关都是中间段关卡，第10关是末关。中间段关卡都是去复制StageMiddle，而最后一关是去复制StageEnd
5.具体去复制的逻辑是：
    1）获取第一关的场景文件夹，第一关的场景文件夹统一都叫Stage001，也就是以Player01举例，路径是Workspace - Home - PlayerHome1 - Stage - Stage001
    2）在stage001下有个叫Base的Part,是基础的战斗地板也就是主要的场景的可活动区域
    3）获取stage001下的Base的基础坐标（CFrame坐标），然后在这个坐标的Z轴上加170，就是新的下一个场景的Base的坐标
    4）不论是StageMiddle还是StageEnd，文件夹下都有叫Base的Part，有了Part的坐标，那整个文件夹的位置就有了，也就是下一关的场景的位置就有了
    5）补充一下，场景文件夹复制出来后要改下名字，固定格式就叫Stage00x，比如第8关，场景虽然复制的是StageMiddle，但是复制出来生成后叫Stage008

开发后修改补充：
我们现在更改下关卡生成时候的规则，补充一个“初始关卡的生成“，也就是stage001，当前的stage001是
默认存在的，我们需要改成用代码去生成。我会提供home到home6的初始的stage坐标，home1：0, 0.5, -185.999；Home2：-120,
0.5, -184；Home3：-240, 0.5, -184；Home4：-360, 0.5, -184；Home5：-480, 0.5, -184；Home6：-600, 0.5,
-184。这些坐标是Base的基础坐标，也就是每个关卡中都有一个叫Base的Part，根据Base放置的坐标，去把整个关卡文件夹复制过来
生成stage001.stage001也是去复制ReplicatedStorage - StageTemplate- Style01 -
StageMiddle。其余后续的关卡生成还是按之前的规则来。

把+170改成了-170

关于兵种位置：

先说我方位置：
在每个关卡文件夹下（比如Stage001）都有一个叫IdleFloor的Part，和上面说的Base是同层级的
也就是比如基地有一个IdleFloor，第一关也有一个IdleFloor，第二关也有一个IdleFloor，每关都有
战斗开始后，兵种需要先从当前位置移动到要挑战关卡的IdleFloor上，并且根据家园中在IdleFloor上的位置信息，走到对应关卡的IdleFloor上站定后，再开始战斗
举个例子就是初始状态下在家园的IdleFloor上站定，点了Play按钮后开始去挑战第一关，此时所有兵种有自己的idleFloor的信息，然后获取Stage001中的IdleFloor上，自己所该属于位置的信息，朝目标寻路，直至到达目标点然后进入待机状态（播放Idle动作）
比如某个兵种在家园的idleFloor上坐标是（3，6），那就朝Stage001里对应的（3，6）前进
每个兵都走这一套寻路逻辑

当所有的兵种都移动到关卡的位置上站定后，立刻开始寻找敌方目标并开始走战斗流程
战斗结束后，如果敌方全部死亡，那剩余的兵种继续重复刚才的流程，朝着下一关的IdleFloor上自己的所属目标前进，然后站定，并开始下一场战斗
直至我方兵种全部死亡

补充说明一下，关卡的信息复制过来后位置是和Stage001同层级的

关于敌方兵种：

在每个关卡文件夹下，都有一个叫IdleFloorEnemy的Part，和上面说的Base以及IdleFloor是同级的
当关卡生成后，需要去ReplicatedStorage - EnemyTemplate - Style01下寻找对应的敌人信息，具体逻辑是：
    1）以第一关Stage001举例，关卡要生成时，去Workspace - Home - Stage - Stage001下寻找IdleFloorEnemy，移除这个IdleFloorEnemy，替换成ReplicatedStorage - EnemyTemplate - Style01 - Stage001下寻找IdleFloorEnemy，移除这个IdleFloorEnemy，替换成ReplicatedStorage
    2）由于ReplicatedStorage - EnemyTemplate - Style01 - Stage001下的IdleFloorEnemy节点下有相关的兵种，此时也会被一起复制过来，复制过来的这些兵种就是敌方的怪物，此时就会被复制过来


这里需要一个关卡敌人生成器，具体作用就是让我使用这个敌人生成器去快速配置关卡，具体逻辑是：

我需要你帮我做一个工具，我只说思路，你可以去构想为了实现这个功能，大概有哪些方式可以做
1.我在游戏运行或者不运行的情况下，去加载ReplicatedStorage - EnemyTemplate - Style01 - Stage001的内容出来，未配置的情况下就是加载了一个part出来
2.我通过ui，去生成兵种，包含等级/兵种，点击按钮后生成在复制出来的part上，然后我来拖动摆放好位置，然后接着生成一个新的兵种
3.我通过点击ui上的保存按钮，可以把当前的摆放信息存放到一个敌方，这就是这一关的兵种信息，包含了位置/兵种/等级等内容
4.我生成的兵种信息保存后不是说我停止运行了就结束了，而是彻底保存下来
5.我想要编辑已经做好的某个关卡时，再加载出来这一关，可以删除兵种或者添加或者移动位置，都可以

以上是这个关卡配置工具的大概思路，我没想明白应该怎么实现，但是我需要这个功能，你来为我进行设计


V2.0.1
新增开门效果：

在我们每个玩家的家园中，以PlayerHome1举例，Workspace - Home - PlayerHome1 - MetalDoor01是我们的家园中的两扇门
常规状态下，玩家刚进入游戏时，门是关上的状态（也就是默认初始状态）

我们现在需要做的是：
1.当玩家点击挑战按钮，进入关卡挑战流程后，需要展开门，具体的表现效果是：
    1）将MetalDoor01 - DoorLeft这个model的Origin下的Orientation的Y轴的数值改成90，初始数值是0
    2）将MetalDoor01 - DoorRight这个model的Origin下的Orientation的Y轴的数值改成-90，初始数值是0
    3）以上两步，都需要在1秒内完成，也就是1秒内从0度变成90/-90，有一个打开门的表现，而不是瞬间打开

以上是每个玩家的家园中都有一个对应的门，每个玩家挑战时都有自己对应的表现

当战斗结束时，清理战场场景的时候，再把门关上，具体表现就是1秒内从打开的90/-90度，再改变成0度


V2.0.2 修改背包系统：

概述：我们当前的背包系统是之前临时用代码构建的，属于测试功能用，现在我们要对背包进行正式的开发

详细规则：

背包界面：
1.在StarterGui - BackpackGui这个ScreenGui是我们的背包界面，背包界面的显示与关闭，就是控制BackpackGui的Enable属性为True或者False
2.每个玩家的家园中都有一个叫IdleFloor的Part，是我们用于摆放兵种的地板。当玩家与IdleFloor接触时，就自动把背包显示出来，当玩家离开了IdleFloor不接触了，就把背包关闭显示


背包信息显示：
我的ui结构时这样的：
BackpackGui（screenGui）
  └─ BackpackFrame（Frame）
      ├─ ItemListFrame（ScrollingFrame）
      │   ├─ UIListLayout（UIListLayout组件）
      │   └─ ArmyItemTemplate（textButton）
      │       ├─ Icon（imageLabel）
      │       ├─ Number（TextLabel）

以上是我背包系统的ui结构

在背包中，有个专门的列表ItemListFrame，用于存放我们的兵种列表
ArmyItemTemplate是我们的兵种信息模板，常规状态下是隐藏的（Visible=false），当出现一个兵种时，就复制一份ArmyItemTemplate并改成兵种的名字，然后显出出来，就达到了展示一个兵种信息的作用
ArmyItemTemplate - Icon是该兵种的图标
ArmyItemTemplate - Number是该兵种当前拥有的数量

注意：这里有个要加的功能就是：要在UnitConfig的兵种配置中，给每个兵种加上icon信息，填资源名称即可

其余的背包内的数量更新逻辑保持不变，就是每次兵种信息数量登发生变化，都要及时更新背包中的兵种信息

另外我们需要加一个优化，关于兵种摆放的：

1.现在每次点击背包中的兵种后就会关闭显示背包，这个逻辑要移除，保持为我们上述的新的显示逻辑，也就是只要玩家在IdleFloor上接触着，就要一直显示背包
2.关于兵种摆放的：
    1）现在是玩家点击放下兵种后，就在鼠标端移除了兵种，想再摆放就需要再次点击兵种
    2）我们需要修改为：如果某个兵种数量大于1，比如有3个，玩家点击该兵种进行摆放摆放成功后，只要该兵种可摆放的数量还大于等于1，就需要在鼠标端立即再生成一个该兵种模型用于摆放，也就是玩家可以通过连续点击来快速摆放多个兵种
    3）当选中的兵种数量变为0时，才移除在鼠标端的兵种模型，并且背包中的兵种数量也要及时更新（也就是变成了0，此时兵种在背包中就消失了）
    4）其余逻辑保持不变，比如回收兵种等逻辑


V2.0.3
关于空气墙的逻辑：
我们当前的代码逻辑下，当玩家挑战关卡时会加载关卡的地图，同时预加载下一关关卡的地图

基于以上逻辑，我们现在需要对这个规则进行一个补充：
1.在我们的每个关卡模板下，比如StageEnd和StageMiddle，都有一个叫做AirWall的Part，这个Part的初始默认碰撞属性为可碰撞=true
2.当关卡被复制出来时，需要把当前关卡的节点下的AirWall的可碰撞属性改成False，下一关的依然保持为True
3.当本关被挑战成功后，需要立刻把下一关场景节点下的AirWall可碰撞属性改成False，同时加载出新的一关的场景，此时新关卡的场景下的AirWall属性依然为False
4.这么做的目的就是为了防止玩家提前跑到下一关去


v2.1
关于兵种购买

概述：我们的游戏中，兵种是需要玩家花费金币进行购买的，玩家可以在商人处购买兵种

商店入口：
1.在我们的游戏基础结构下，Workspace下有个Home文件夹，Home下有多个子文件夹比如从PlayerHome1到PlayerHome6，作为每个玩家进入游戏后的独立的家园
2.然后在每个玩家的家园文件夹下，以PlayerHome1举例，有两个商人NPC模型，一个叫KeepShoper01，另外一个叫KeepShoper02
3.KeepShoper01是兵种购买商店的NPC，KeepShoper02是技能购买商店的NPC，这个版本我们暂时只做兵种购买商店的NPC
4.当玩家靠近自己家的NPC模型也就是KeepShoper01时，需要自动打开商店界面，也就是把StarterGui - ArmyStore - StoreBg的Visible属性改成True
5.当玩家远离自己家的NPC模型也就是KeepShoper01时，需要自动关闭商店界面，也就是把StarterGui - ArmyStore - StoreBg的Visible属性改成False

商店系统：
1.玩家只能在自己家的商店购买兵种，无法去其他家的商店购买兵种，去到其他家也无法触发对方商店的打开逻辑
2.我们需要设定一张专门的商店表，表中填写可以在商店中购买到的兵种，只有填写在这个兵种商店表中的兵种，才可以在该商店中出现并供玩家购买
3.填写在兵种商店表中的兵种（填兵种配置表中的UnitId即可），需要有多个基础配置：
    1）基础等级，决定了该兵种出售时是出售的几级兵，基础默认都是1级，也就是只能买到1级的某某兵种
    2）金币价格，决定了买一个这个兵种的金币价格
    3）刷新概率，决定了每次库存更新时，有多少概率这个兵种会出现可购买数量（库存逻辑下面会详细说）
    4）库存上限：决定了刷新时如果判定可被购买，那么刷新时最多刷多少个库存
    5）库存下限：决定了刷新时如果判定可被购买，那么刷新时最少刷多少个库存
    6）罗布币价格，决定了买一个兵种的罗布币价格，这里只是信息显示，具体价格根据开发者商品信息来
    7）开发者商品id：决定了使用罗布币购买时对应的开发者商品id
4.库存刷新逻辑：
    1）从玩家进入游戏后开始倒计时，玩家加入游戏时先瞬间立刻刷新一波库存，然后开始倒计时5分钟，5分钟后刷新一波库存，循环往复，这个5分钟要可以配置
    2）玩家离线时需要记录离线时间，玩家再次上线时比对二者的时间差，如果小于5分钟（配置的时间），则不立即刷新，而是继续倒计时，倒计时是刷新间隔减去离线时间，比如刷新倒计时5分钟，玩家离线2分钟，再进来从3分钟开始倒计时，结束后再刷新，这么做是为了防止玩家恶意刷库存
    3）在我们的商店表中会配置：某个兵种的刷新概率，这个概率决定了本次刷新后，该兵种的库存是否是0，比如填60%，就是有60%的概率不是0，有40%的概率是0
    4）如果刷新时某个兵的库存数上一步已经判定不是0了，那么需要决定本次刷新的库存数，也就是从库存下限到库存上限之间的范围随机一个数，比如下限是3，上限是6，就从这之间随机一个整数，作为本次刷新后的这个兵种的库存数量
5.库存数量逻辑：
    1）库存数量决定了玩家可以在商店内购买的兵种数，每买一个，该兵种库存就减1
    2）当某个兵种的库存数量为0时，就无法购买

商店信息展示：
1.在我们的商店界面中，按顺序展示我们可购买的兵种的信息，具体排序从上到下就按我们配置表中的顺序排序即可
2.具体的界面结构是：
StarterGui
└── ArmyStore（ScreenGUi）
    └── StoreBg（frame）
        ├── ScrollingFrame（ScrollingFrame）
        │   ├── UIListLayout
        │   └── BuyButtonFrame（frame）
        │       ├── GoldBuy(imageButton)
        │           ├── Price(textLabel)
        │       ├── RobuxBuy(imageButton)
        │           ├── Price(textLabel)
        │   └── ItemCardTemplate（frame）
        │       └── IconBg（frame）
        │           ├── Icon(imageLabel)
        │       └── ATK(textLabel)
        │       └── RANGE(textLabel)
        │       └── HP(textLabel)
        │       └── Level(textLabel)
        │       └── Name(textLabel)
        │       └── Number(textLabel)
        │       └── Price(textLabel)
        │       └── Quality(textLabel)
        ├── CloseButton(imageButton)
        └── Title(textLabel)
具体的客户端规则是：
1.BuyButtonFrame是一个Frame，常驻状态下的visible属性是false
2.BuyButtonFrame下面分别是GoldBuy和RobuxBuy这两个按钮，分别用于代表触发金币购买还是罗布币购买，在我们的商店表中有配置每个兵种用罗布币购买时候的开发者商品id
3.GoldBuy和RobuxBuy下面都有一个叫Price的TextLabel，用于显示价格文本，GoldBuy下的Price显示格式为XXX $,XXX代表金币数值，RobuxBuy下的Price显示格式为XXX R$，XXX是配置的罗布币价格
4.ItemCardTemplate是我们的兵种卡片信息模板，常规状态下是Visible属性为False，当商店形成时，根据兵种信息去复制一份ItemCardTemplate，把visible属性改成true，把其下的各种属性改成该兵种的对应信息，就时商品卡片
5.ItemCardTemplate下的各种结构信息为：
    1）ATK代表攻击力，显示该兵种当前等级的基础攻击力
    2）RANGE代表近战还是远程，在兵种配置unitConfig中有关于近战还是远程的文本说明配置，使用对应的文本即可，比如Melee是近战，Ranged是远程
    3）HP代表血量，显示该兵种当前等级的基础血量
    4）Level代表等级，显示该兵种的等级，格式固定为Lv.XXX
    5）Name代表兵种名字
    6）Number代表库存数量，格式固定为X（这是乘号）Y，Y代表固定数量
    7）Price代表金币价格，显示格式固定为XXX $
    8）Quality代表品质，这个我们需要在兵种表unitConfig中增加一个字段用于显示品质，默认全部为Common（品质我们后续再拓展，这里先全部Common）
6.CloseButton是关闭按钮，点击后关闭商店界面（也就是把StarterGui - ArmyStore - StoreBg的Visible属性改成False），手动关闭后就算玩家在NPC范围内也不立刻开启界面，需要玩家先离开再进来才再次显示
7.Title是一串文本，用于显示当前的库存刷新倒计时，格式固定为：Stock refreshes in XX:YY，XX:YY代表分秒，界面打开时需要实时更新倒计时

这里有一些补充：玩家金币购买的时候不需要二次确认，直接扣除金币并加入玩家背包对应的兵种即可
在购买过程中由于库存正好刷新，如果在刷新前确实库存数量大于等于1且刷新完成为0了，也要允许购买，扣除金币并发放一个道具

关于ScrollingFrame中的卡片列表和购买有一定的规则：
1.商店展开时会复制多个商品信息形成商品列表，按照UIListLayout的排序进行排序即可
2.BuyButtonFrame常规是不可见的，所以在UIListLayout中不占据位置，但是当玩家点击某个商品卡片时，需要：
    1）立即将BuyButtonFrame移动到卡片所在位置（整个卡片的中心处）背后，二者中心正好对准
    2）再立刻把BuyButtonFrame插入到该商品与另一个商品之间（占据一个UIListLayout位置），把下面的卡片挤到更下面的位置，形成一个下拉展开的效果
    3）再次点击该卡片可以收起BuyButtonFrame，如果在显示BuyButtonFrame的时候玩家又点击了另一个卡片，则需要把BuyButtonFrame先立刻收起来，再走一遍新点击的出现流程效果
    4）BuyButtonFrame下的GoldBuy和RobuxBuy显示的价格需要实时更新为本次点击的卡片对应的价格，点击购买也是触发对该卡片对应商品的购买
    5）卡片和按钮点击时我希望有一个通用的点击缩小松开放大的效果，这个最好做成通用功能，后面出现的新按钮都要有这个效果
    关于以上说的这个效果，本质上是一个下拉列表，具体逻辑可以参考下面这段代码，下面这段你确实是实现了我要的效果的，除了没有移动效果现在只是硬切：

-- 将此脚本放在 StarterPlayer.StarterPlayerScripts 中
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待界面加载
local armyStore = playerGui:WaitForChild("ArmyStore")
local storeBg = armyStore:WaitForChild("StoreBg")
local scrollingFrame = storeBg:WaitForChild("ScrollingFrame")
local buyButtonFrame = scrollingFrame:WaitForChild("BuyButtonFrame")

-- 初始化
local currentExpandedCard = nil
local originalLayoutOrders = {} -- 存储原始LayoutOrder值

-- 隐藏购买按钮
buyButtonFrame.Visible = false

-- 获取所有ItemCard
local function getItemCards()
	local cards = {}
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name == "ItemCard" then
			table.insert(cards, child)
		end
	end
	return cards
end

-- 获取卡片在列表中的索引
local function getCardIndex(targetCard)
	local cards = getItemCards()
	for i, card in ipairs(cards) do
		if card == targetCard then
			return i
		end
	end
	return 0
end

-- 获取目标卡片之后的所有卡片
local function getCardsBelow(startIndex)
	local cardsBelow = {}
	local allCards = getItemCards()

	for i = startIndex + 1, #allCards do
		table.insert(cardsBelow, allCards[i])
	end

	return cardsBelow
end

-- 展开卡片
local function expandCard(card)
	local cardIndex = getCardIndex(card)

	-- 存储原始LayoutOrder值
	if not originalLayoutOrders[card] then
		originalLayoutOrders[card] = card.LayoutOrder
	end

	-- 设置购买按钮的位置和属性
	buyButtonFrame.Parent = scrollingFrame
	buyButtonFrame.LayoutOrder = card.LayoutOrder + 1
	buyButtonFrame.Visible = true

	-- 调整后续卡片的LayoutOrder，使它们下移
	local cardsBelow = getCardsBelow(cardIndex)
	for _, belowCard in ipairs(cardsBelow) do
		if not originalLayoutOrders[belowCard] then
			originalLayoutOrders[belowCard] = belowCard.LayoutOrder
		end
		belowCard.LayoutOrder = belowCard.LayoutOrder + 2
	end

	currentExpandedCard = card
end

-- 收起卡片
local function collapseCard(card)
	-- 隐藏购买按钮
	buyButtonFrame.Visible = false

	-- 恢复所有卡片的原始LayoutOrder
	for cardObj, originalOrder in pairs(originalLayoutOrders) do
		cardObj.LayoutOrder = originalOrder
	end

	-- 清空存储的原始顺序
	originalLayoutOrders = {}
	currentExpandedCard = nil
end

-- 处理卡片点击
local function onCardClick(clickedCard)
	if currentExpandedCard == clickedCard then
		-- 点击已展开的卡片：收起
		collapseCard(clickedCard)
	else
		-- 点击新卡片：先收起之前的，再展开新的
		if currentExpandedCard then
			collapseCard(currentExpandedCard)
		end
		expandCard(clickedCard)
	end
end

-- 为所有卡片绑定点击事件
local function setupCards()
	local cards = getItemCards()

	-- 确保所有卡片有正确的LayoutOrder
	for i, card in ipairs(cards) do
		card.LayoutOrder = i * 10 -- 使用10的倍数，以便在中间插入按钮

		-- 确保卡片可以被点击
		if card:IsA("Frame") then
			local clickDetector = card:FindFirstChildOfClass("TextButton") or Instance.new("TextButton", card)
			clickDetector.Size = UDim2.new(1, 0, 1, 0)
			clickDetector.BackgroundTransparency = 1
			clickDetector.Text = ""
			clickDetector.ZIndex = 10

			-- 绑定点击事件
			clickDetector.MouseButton1Click:Connect(function()
				onCardClick(card)
			end)
		else
			-- 如果卡片本身就是按钮，直接绑定事件
			card.MouseButton1Click:Connect(function()
				onCardClick(card)
			end)
		end
	end
end

-- 初始化UI
setupCards()


商品购买：
1.商品购买时如果判定货币足够就扣除金币然后为玩家发放道具，加入背包中

关于金币数值显示：
1.StarterGui - MainGui - CoinNum是我们的金币数值，格式固定为$XXXXX
2.现在我们需要做一个效果：金币数值发生变化时，需要有一个快速的金币数值滚动的效果，时长大概1秒左右，快速从A值变化成B值


V2.2 关于兵种头顶等级颜色变化

我们的兵种头顶有等级信息展示，为了在一堆兵放在一起时能够清楚看到每个兵的等级信息，我决定对不同等级赋予不一样的字体颜色与描边颜色

在我们当前的兵种头顶等级信息展示的逻辑与路径保持不变的情况下，有几个现状：
1.头顶名字显示是BillboardGui下一个叫TextLabel的TextLabel,其下有一个描边子节点来控制字体的描边，我们需要做的就是对字体的颜色和描边的颜色做修改

我们需要有一个单独的配置，用于配置不同等级时，字体的颜色/描边的颜色。具体的数值是：

LV.1：字体颜色：255, 255, 255，描边颜色：0, 170, 0
LV.2：字体颜色：255, 255, 255，描边颜色0, 80, 255
LV.3：字体颜色：255, 255, 255，描边颜色170, 0, 255
LV.4：字体颜色：255, 255, 255，描边颜色255, 100, 0
LV.5：字体颜色：255, 255, 255，描边颜色255, 0, 0

有个特殊规则：
当前等级是最高级时，我们固定显示是Lv.Max，这是已经实现的逻辑
当等级已经是最高级时，最高级的字体颜色固定为0, 0, 0，描边颜色固定为255, 0, 0
也就是说当达到最高级时，固定就是这个表现了，比如2个2级合了一个3级，但是3级是最高级，这时候就强制使用最高级的颜色表现而不是使用第3级的表现


需求文档V2.3 血条功能

概述：
我们现在多兵种之间战斗，是需要实时看到兵种头顶的血量信息的，所以我们需要开发一个血条功能

具体逻辑是：

1.开战后，需要立刻隐藏角色头顶的等级信息，并给角色创造一个血条
2.隐藏头顶等级信息就是把原来角色的等级那个BillboardGui的Enable属性改成false
3.创造血条就是去ReplicatedStorage下面寻找一个叫HpTemplate的BillboardGui，加载给角色，和等级同层级，也就是在角色的Head这个节点下，把Enable属性设定成true，就是显示出来了血条

血条逻辑：

1.血条结构组成是：HpTemplate是一个BillboardGui，下面有一个叫Bg的Frame，再其下有一个叫Hpprogressbar的Frame，Hpprogressbar是血条，用来动态变化对应血量信息的
2.满血时Hpprogressbar的大小（就是X的Size，用Scale，大小时0.998，代表满血，当死亡时，大小设为0，此时血槽就空了角色死亡）
3.角色死亡的时候要移除头顶的血条
4.角色在基地复生的时候，要重新把等级信息给显示出来


需求文档V2.4  战斗结束界面

概述：
在我们的挑战关卡过程中，会有一个战斗结束的过程。现在的处理是直接复生角色并移除场景。现在我们要接入“结算流程”这个步骤

详细需求：
当战斗结束后（不论是我方全部死完还是我通关了全部关卡），先不复生，不移除场景，而是立刻弹出结算界面（将角色ui的StarterGui - Victory下的Back/Effect/Information这三个Frame的Visible属性改成True
玩家只有点击Victory - Information - Confirm这个按钮，才可以算战斗结束，即：
1）移除场景
2）将玩家立刻传送到出生点
3）兵种走复生逻辑
4）将角色ui的StarterGui - Victory下的Back/Effect/Information这三个Frame的Visible属性改成false

V2.5  敌我区分

我们在战斗过程中我方小兵与敌方小兵需要做出区别来，具体区分就是在血条颜色/角色模型描边/冒字颜色区分上

详细需求：
1.血条颜色：在血条生成时，我方兵使用当前默认的血条效果即可，敌方的兵头上的血条生成时，需要额外把血条的Hpprogressbar的颜色改成红色255，0，4
2.敌方的兵种刷新时，需要把每个兵种模型下的Highlight这个节点的OutlineColor颜色改成255，0，4，并且把FillTransparency改成0,把OutlineTransparency值改成0
3.在造成伤害时，我方对敌方造成的伤害和敌方对我方造成的伤害冒字效果也要修改，我方打敌方：白色字体冒字，敌方打我方，红色字体冒字


V2.6
离线金币产出：

我们需要给游戏加入挂机金币的功能，玩家离线后，再次上线时会根据玩家的离线时间来获得金币，具体逻辑是：
1.挂机金币产出速度根据分钟计算，目前暂定10金币/分钟，这个走参数控制，不要写死
2.玩家离线时，记录玩家的离线时间，玩家再次上线时，计算玩家的离线分钟数，并根据离线分钟数与挂机速度来为玩家生成离线金币
3.注意：最多产出6小时的离线金币，如果离线时间超过6小时，则最多算6小时的离线金币

详细的客户端逻辑是：
1.每个玩家的家园下都有一个叫Mail的模型，是我们的挂机金币领取的地方，玩家靠近Mail模型，自动弹出系统默认的交互键（也就是那个E键），玩家长按1秒。可以领取挂机金币
2.Mail模型下有个叫IdleEarnings的Part，其下有个叫Fighting的BillboardGui，在Fighting下有个叫Bg的Frame，在Bg下有个叫Number的TextLabel，这个用来显示当前的挂机金币数量，格式是XXXX$
3.金币被领取后，挂机可领取金币数量清零
4.同时在Mail下有个叫CoinsTrigger的Part，其下有ParticleEmitter01/ParticleEmitter02/ParticleEmitter03三个粒子发射器，玩家领取的时候，需要把这三个粒子发射器的释放的Enabled属性改成True，然后1秒后改成False

加一个测试命令，使用命令后，可以直接生成1小时的挂机金币让我领取


V2.7 开战表现

概述：
我希望战斗开始后，会锁定战斗镜头，镜头始终对准我方兵种的阵型中心，然后玩家跟在我方兵种后方自动奔跑跟着战斗

详细需求：

1.玩家点击Attack按钮后进入战斗，这时，需要立刻移动镜头，对准IdleFloor，并且镜头随着兵种的移动，也跟着往前推进，此时镜头是锁定的，玩家无法通过滑动屏幕而解除镜头的锁定
2.在每个玩家的Home（即PlayerHomeX）下，都有一个叫CommandPart的Part，当玩家点击了Attack按钮后，需要立刻把玩家传送到CommandPart的位置站住，并限制玩家的移动操作比如移动转轮或者按方向键移动，之后的移动都由系统控制玩家的移动
3.点击attack后，从玩家当前的镜头情况，立刻快速0.5秒内将镜头平滑变换为对准IdleFloor也就是对准我们的军队
4.随着兵种开始移动，我们的镜头始终对准兵种中心，跟随兵种移动，当兵种停止移动，我们的镜头也停止移动，最终效果就是镜头始终跟随着ui
5.战斗结束后玩家点击了胜利页面的Confirm按钮后，解除镜头锁定并走正常的复生流程

关于镜头跟随的逻辑，大概是这样的需求：
计算“质心”（Center of Mass）

这是最平滑且不易出错的方式。原理： 脚本会每一帧（Frame）获取当前场上所有存活的我方单位（Soldiers）的位置坐标。计算： 将所有兵的 X 轴和 Z 轴坐标相加，然后除以兵的总数量。$$目标位置 = (兵A坐标 + 兵B坐标 + ... + 兵N坐标) / N$$
这个镜头的逻辑公式大概率是这样的：$$镜头目标位置 = \text{Lerp}(\text{当前位置}, \frac{\sum \text{所有兵的位置}}{\text{兵的总数}} + \text{固定俯视偏移量}, \text{平滑系数})$$它做到了：前排停，后排挤，镜头缓停；全军覆没，镜头才会没目标。

具体实现需求大概是：
核心脚本 (The Script)
这个逻辑必须在客户端运行，以保证最流畅的帧率。

在 StarterPlayer -> StarterPlayerScripts 中创建一个 LocalScript。

命名为 CameraController。

粘贴以下代码：

Lua

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- 配置区域
local TROOPS_FOLDER_NAME = "Troops" -- 你的兵存放的文件夹名字
local OFFSET = Vector3.new(0, 15, 20) -- 镜头相对于中心点的偏移 (x, y, z) -> y是高度，z是后退距离
local SMOOTHNESS = 0.1 -- 平滑度 (0.01 - 1)，数值越小越平滑，但也越有延迟感

-- 获取引用
local camera = Workspace.CurrentCamera
local troopsFolder = Workspace:WaitForChild(TROOPS_FOLDER_NAME)

-- 设置相机为Scriptable，否则默认的Roblox相机逻辑会干扰
camera.CameraType = Enum.CameraType.Scriptable

-- 核心计算函数
local function updateCamera()
	local troops = troopsFolder:GetChildren()
	local totalPosition = Vector3.zero
	local activeCount = 0
	
	-- 1. 遍历并计算所有存活单位的位置总和
	for _, troop in ipairs(troops) do
		-- 确保兵有身体且活着 (可选: 检查 Humanoid.Health > 0)
		local rootPart = troop:FindFirstChild("HumanoidRootPart")
		if rootPart then
			totalPosition = totalPosition + rootPart.Position
			activeCount = activeCount + 1
		end
	end
	
	-- 如果没有兵（比如刚开始或者全死光了），就不更新镜头，或者可以设定一个默认点
	if activeCount == 0 then
		return 
	end
	
	-- 2. 计算平均中心点 (质心)
	local centerPosition = totalPosition / activeCount
	
	-- 3. 计算目标镜头位置 (中心点 + 固定的偏移量)
	local targetPosition = centerPosition + OFFSET
	
	-- 4. 构造目标CFrame (位置在 targetPosition，脸朝向 centerPosition)
	local targetCFrame = CFrame.new(targetPosition, centerPosition)
	
	-- 5. 使用 Lerp 进行平滑移动
	-- 这一步实现了“兵停镜头缓停”的效果
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, SMOOTHNESS)
end

-- 每一帧渲染前执行一次
RunService.RenderStepped:Connect(updateCamera)
第三步：代码原理解析（为什么这样写？）
totalPosition / activeCount: 这就是数学上的求平均值。

如果有1个兵在坐标(0,0,0)，中心就是(0,0,0)。

如果加了1个兵在(10,0,10)，中心自动变成(5,0,5)。

效果： 当新的兵加入时，镜头会微妙地调整位置以容纳大家；当兵移动时，中心点随之移动。

CFrame.new(targetPosition, centerPosition): 这是Roblox的一个构造函数：CFrame.new(我站在哪, 我看哪里)。 这确保了无论兵怎么走，镜头始终聚焦在队伍的中心。

RenderStepped: 这是保证镜头不卡顿的关键。它会在画面渲染的每一帧都运行。如果不在这里运行，镜头会有严重的拖影或抖动。

第四步：进阶优化（让手感达到商业级）
基础代码已经能用了，但如果你想达到视频里那种完美的体验，建议加上这两个功能：

1. 动态缩放 (Dynamic Zoom)
问题： 兵少的时候镜头刚好，兵变多了（比如变成了500个），屏幕装不下了怎么办？ 方案： 根据兵的数量动态调整 OFFSET。

修改代码中的第3步逻辑：

Lua

    -- 动态计算高度和距离
    -- 基础距离 + (每个兵增加 0.1 的距离，最大限制为增加 30)
    local dynamicZoom = math.min(activeCount * 0.1, 30) 
    
    local currentOffset = OFFSET + Vector3.new(0, dynamicZoom, dynamicZoom)
    local targetPosition = centerPosition + currentOffset
这样当你的队伍壮大时，镜头会自动拉高、拉远，让玩家能看到整个军团，非常有成就感。

2. 锁定 X 轴 (可选)
场景： 很多这类游戏是跑酷类的，主要往 Z 轴（前方）跑。如果你不希望兵往左边跑时镜头也跟着往左甩（导致画面晃晕），你可以锁定 X 轴。

Lua

    -- 仅使用计算出的 Z 轴 (前进方向)，X 轴固定为 0 或地图中心
    local fixedCenter = Vector3.new(0, centerPosition.Y, centerPosition.Z)
    local targetPosition = fixedCenter + OFFSET
    local targetCFrame = CFrame.new(targetPosition, fixedCenter)


V2.8  基地房屋替换

1.给我们的关卡添加章节概念：
    1）我们的关卡共分了多个章节，每个章节下有多个小关，目前我们的关卡配置里的其实视为一个章节下的3个小关
    2）给目前关卡全部设定为第一章，然后共3关，再给我加一个第二章，也是一样的数据共3关
2.当我成功通过了某个章节的所有关卡后，自动弹出结算界面走战斗结束流程，此时视为我通关了这一章，以后我再挑战就是要挑战下一章了
3.如果我一直没挑战成功这一章的所有关卡，那下次再挑战依然是挑战这一章从第一关开始
4.如果我已经战胜了最后一章，再挑战后，也依然继续挑战最后一章即可，比如当前共2章但是我通关了，那再挑战也还是挑战第二章的关卡

关于房屋替换：
1.我们每个家园都有一个默认房屋，房屋模型是Home - PlayerHomeX - House - PrisonLv1（这是当前的默认房屋的模型）
2.我们需要一张额外的配置表，用来配置我们的每个房屋模型，是在通关了第几章之后替换的
3.通关了某个目标章节后，就把我们的房屋模型替换为配置的这个模型
4.模型路径是ReplicatedStorage - House - 模型名称。目前模型只有PrisonLv1和PrisonLv2，PrisonLv1是初始的房屋，通关章节填0即可，PrisonLv2帮我填通关章节是1
5.当我通关完成回到家园后，家园的房子要立刻替换，也就是把旧房屋模型删了换成新房屋模型，并且位置不要变



需求V3.0 -技能系统

概述：游戏中有技能系统，玩家可以通过释放技能，影响战场，本版本中技能的获取暂时使用gm指令获取

技能唯一性：
1.每个技能都有一个单独的技能id，同时对应有技能名字/技能图标/技能类型等属性
2.技能是消耗品，每消耗一个技能，就扣除一个对应库存，如果技能消耗完了，就无法再使用技能了，必须再次获取技能才能使用

技能特性：
1.技能名字在技能表中进行配置
2.技能图标在技能表中进行配置
3.技能类型分为：伤害型/治疗型/增益型
4.每个技能的逻辑建议都单独封装单独实现即可

技能背包：
1.在我的ui结构中，StarterGui - SkillBackpackGui是我们创建的用于展示当前拥有的技能数量的背包的ScreenGui，在SkillBackpackGui下有个叫BackpackFrame的Frame
2，在BackpackFrame下面有个叫ItemListFrame的ScrollingFrame，是用于展示玩家拥有的技能列表的，在ScrollingFrame下面有个叫SkillTemplate的节点，是我们的技能展示模板
3.当需要加载技能信息时，去复制SkillTemplate，将复制出来的节点的visible属性改成true。SkillTemplate下有个叫Icon的，用于展示技能的图标icon，SkillTemplate下有个叫Number的textlabel,用于展示该技能当前的拥有数量，格式是*X,X是拥有数值
4.当玩家点击战斗开始后，立刻将StarterGui - SkillBackpackGui - ItemListFrame的visible属性改成true，当战斗结束后，再立刻把visible属性改成false
5.玩家每消耗掉一个技能，都会需要扣除一个对应的技能数量

技能效果：
技能1：喷水枪
技能ID：1001
对应的资源名：WaterGun
技能效果：对范围内所有敌人造成100点真实伤害
技能icon：rbxassetid://120383806488759
技能类型：伤害型
技能范围：100

技能2：毒气炸弹
技能ID：1002
对应的资源名：PoisonGas
技能效果：对范围内的所有敌人造成100点真实伤害
技能icon：rbxassetid://108132069408183
技能类型：伤害型
技能范围：100


技能3：大火
技能ID：1003
对应的资源名：Molotov
技能效果：对范围内的所有敌人造成持续伤害，每0.5秒造成20点伤害，持续4秒
技能icon：rbxassetid://119660478028982
技能类型：伤害型
技能范围：100


技能范围效果描述：
1.我们的技能暂定都是圆形范围内生效
2.当填技能范围是100时，代表是一个直径为100studs范围的圆形
3.技能释放时，在技能释放范围内的目标都会收到技能影响，范围是以圆心来判断即可，下面会描述

技能释放：
1.点击技能背包中的技能icon，可触发技能释放流程
2.在我们的ReplicatedStorage中，有一个叫SkillPreview的Part，用于做技能释放时的位置预览
3.点击技能icon后，立刻在玩家的鼠标端出现SkillPreview这个Part，part始终贴地，并且实时跟随玩家的鼠标移动而移动，始终保持在鼠标端
4.在SkillPreview出现的情况下，玩家再次点击鼠标左键，就SkillPreview当前的位置释放技能，玩家点击右键可以取消释放
5.SkillPreview的圆心位置出现在鼠标的尖端时，需要根据该技能的范围，将SkillPreview的size的Y和Z的值都调成技能的范围的值
6.技能释放时，就以当前SkillPreview的位置计算伤害范围，在范围内的敌人都会收到伤害


关于技能表现：
1.在ReplicatedStorage中有个文件夹叫Skills，下面存放着我们的技能资源
2.每个技能表中都有填对应的资源名，就是对应这个路径下的资源名
3.释放技能时，就是去路径下找到对应的资源，把这个Part下的所有内容全部在释放位置复制出来，然后3秒后移除即可

技能伤害：
技能造成的伤害也要有伤害冒字，按我方对敌方造成的伤害颜色来显示
一次性伤害技能在技能释放瞬间就造成伤害，持续性伤害在释放瞬间计算第一次伤害，然后倒计时期间持续根据我们的伤害时间间隔造成伤害即可

关于gm命令：
使用命令直接添加技能即可，比如：/addskill 1001 1，代表加1个1001这个技能



V3.1技能购买商店

概述：
我们可以在商店中通过使用金币购买技能，技能在商店中的刷新逻辑和库存逻辑与兵种商店类似

详细规则：
1.玩家靠近技能商人（自家文件夹下的KeepShoper02这个模型，兵种商人是KeepShoper01），打开技能商店界面
2.打开技能商店页面就是把StarterGui - SkillStore - StoreBg这个frame的visible属性改成true
3.点击StarterGui - SkillStore - StoreBg - CloseButton这个按钮可以关闭界面，或者玩家离开技能商人范围自动关闭（把StarterGui - SkillStore - StoreBg这个frame的visible属性改成false）

技能列表：
1.StarterGui - SkillStore - StoreBg - ScrollingFrame，这是个ScrollingFrame，用于展示技能列表
2.在ScrollingFrame下有个叫ItemCardTemplate的模板，是技能信息的模板，常规的visible属性是false，技能卡片生成时就是去复制一份这个模板，改对应信息，然后把visible属性改成true，就形成了一个技能的卡片
3.ItemCardTemplate - IconBg - Icon是一个imagelabel，用于展示该技能的图标
4.ItemCardTemplate - Name是一个textlabel，用于展示技能的名字
5.ItemCardTemplate - Number是一个textlabel，用于展示技能的库存数量，格式是xY，Y是库存数值，x是乘号
6.ItemCardTemplate - Price是一个Textlabel，用于展示这个技能的价格，格式是XXX$，XXX是金币价格
7.
技能列表：
1.StarterGui - SkillStore - StoreBg - Title是倒计时，与兵种商店显示内容一样，内容也是Stock refreshes in XX:YY，与兵种商店逻辑一致

技能库存逻辑：
与兵种商店共享同一个刷新周期，也就是以前兵种商店只刷自己，现在连兵种商店一起刷新

库存数量：
1.新增一个技能商店表
2.每个技能配置数量上限和数量下限，然后再添加刷新概率，概率就是0到1，1就是每次都刷新库存，0.5就是每次刷新时有0.5概率库存是0，0.5概率是从上限到下限的范围内随机一个值
3.每买一个，就减少一个库存，库存为0就不能购买了

购买逻辑是：
1.玩家点击技能卡片，就把SkillStore - StoreBg - ScrollingFrame - BuyButtonFrame的visible属性改成true并加到列表中排在这个卡片后面（这里逻辑可以看兵种商店，一样的逻辑）
2.BuyButtonFrame下的GoldBuy是金币购买链接，点击触发金币购买，BuyButtonFrame下的RobuxBuy是罗布币购买链接，点击触发罗布币购买
3.这里需要补充一个：每个技能需要加一个字段在技能表中，填这个技能对应的开发者商品id
4.购买逻辑与货币扣除逻辑等都走和兵种购买一样的逻辑
5.花费货币购买的技能是永久数据要进行保存
6.GoldBuy- Price是一个textlabel，用于显示金币价格，格式是XXX$，RobuxBuy - Price是一个textlabel，用于显示罗布币价格


V3.2 Loading功能

概述：我们的游戏中有很多的资源需要提前加载，为了保证游戏的体验，需要提前加载好，加载的过程中需要使用loading功能来告诉玩家正在加载

每次打开游戏时需要先进行加载

详细规则：
1.加载过程中，需要把StarterGui - Loading - Bg的Visible属性改成True，这是我们的整个loading页面的父节点
2.StarterGui - Loading - Bg - LoadingImage是背景图，在把Bg的visible属性改成true之前，先从rbxassetid://98877166419333以及rbxassetid://111664305611167以及rbxassetid://136231844959584中随机一张图，设置为LoadingImage的图片内容，这是loading页面
3.StarterGui - Loading - Bg - ProgressBg是加载进度条背景，StarterGui - Loading - Bg - ProgressBg - Progressbar是进度条填充，加载进度为0的时候，Progressbar的size的X值是0，进度为1的时候，Progressbar的size的X值是1（这里用的值是scale）
4.StarterGui - Loading - Bg - ProgressBg - Number是加载进度数值，格式为XX%，代表加载进度
5.加载进度变化时，需要进度与加载进度数值实时变化
6.当加载完成时，进度填满并且加载进度数值变成100%，然后把StarterGui - Loading - Bg的Visible属性改成False



V3.3 任务部分
概述：我们需要一套简易的任务系统，作为玩家加入游戏初期的指引系统，通过任务系统帮助玩家快速了解游戏玩法

详细规则：
任务类型：
1.类型1：购买N次兵种，N是参数，在任务详情里填写，购买任意兵种都可以
2.类型2：将N个兵布置到战场，N是参数，在任务详情里填写，从任务出现开始计数（我是指把这个任务的前置任务奖励领取了后轮到了这个任务才开始计数）
3.类型3：购买N次技能，N是参数，在任务详情里填写，任意购买一次技能即可
4.类型4：完成一场战斗：点击attack后到弹出结算界面回到基地算完成一场战斗
5.类型5：领取一次挂机金币奖励，只要成功领取一次挂机金币奖励即可
6.类型6：合成一个2级的XXX兵

任务奖励：
1.我们暂时所有任务都固定只有一种奖励类型，那就是增加金币，在奖励字段里填的数值就是奖励的金币数值

任务继承：
1.任务是线性任务，只有完成了当前的任务并领取了当前任务的任务奖励，才在界面上刷新下一个任务
2.任务数据是线性的永久保存的数据，不会因为玩家离线而重置任务进度
3.任务全部完成后，任务界面隐藏即可

我们的所有任务都是必须当前任务领取了奖励，刷新出下一个任务后，下一个任务的完成条件才开始计数，任务未刷新前完成任务条件不计算入任务完成
当前任务的任务进度也是需要保存继承的，比如买3个技能，玩家买了1个技能，进度是1/3，下线后再上线还是1/3

注意当用户完成了最后一个任务后，只是记录这个任务的完成id，不要视为以后都不打开任务系统了，因为后续运营中有可能会添加新的任务，更新后玩家需要继续刷新新增的任务


任务列表：
以下是我的当前暂定的任务列表，需要你转成对应的任务配置表

任务id	任务类型	任务参数	任务描述	奖励数量
1001	1	1	购买任意一个囚犯	100
1002	4	1	完成一场战斗	100
1003	1	1	购买任意一个囚犯	100
1004	4	1	完成一场战斗	100
1005	2	3	将3个囚犯布置到战场中	100
1006	4	1	完成一场战斗	100
1007	3	1	购买一次技能	100
1008	1	1	购买任意一个囚犯	100
1009	4	1	完成一场战斗	100
1010	5	1	领取一次挂机奖励	100

关于任务的客户端逻辑：

1.当玩家有未完成的任务系统时，就始终打开任务界面，即把StarterGui - Task - Bg这个Frame的visible属性改成true，关闭任务界面时就是把visible属性改成false
2.当点击attack按钮进入战斗流程后，把任务界面关闭，退出战斗流程回到基地后，如果还有未完成的任务，就再把任务界面显示出来
3.Bg下有个节点叫RedPoint，是红点，常规的visible属性是false，当前任务完成后但是没有领取奖励时，红点显示，把visible属性改成true，当领取 完成后刷新成下一个任务，并如果下个任务未完成就把红点隐藏
4.Bg - RewardIconBg - Number是个textlabel，用于显示该任务的金币奖励数值
5.Bg - TaskText是任务详情描述，读任务的描述即可，格式是：XXXXX（M/N）,其中XXX是任务详情，M是当前进度，N是要求进度，比如1/3，就代表参数要求是3，当前完成了1
6.当最后一条任务完成后，就把任务界面隐藏


V3.4 金币获取

概述：
这部分需求是关于战斗中金币获得的相关逻辑，具体需求是：

1.在战斗过程中可以获得金币，有两种方式：1.计算战场中心，战场中心每前进30studs，获得X点金币2.每杀死一个敌方兵获得X点金币，每个兵配置基础金币数值
2.关于前进时的金币逻辑是：
    1）开始攻击后，以玩家站立的CommandPart的位置为起点，随着兵种往前移动，战场中心也在移动，此时战场中心每往前移动Xstuds，就获得一次金币，金币数值是Y，这俩都走配置
    2）只算前进，如果战斗过程中战场中心回退了，不扣除金币
    3）每个距离只能获得一次，比如前进了100studs，我们规定是每20获得一次金币，到了100后又回到30，那战场中心从30再回到100这过程是不获得金币的，只有100到120时会再获得一次金币

3.关于击杀兵种获得金币：
    1）每个兵种配置基础击杀金币数值
    2）杀死这个兵时获得金币
    3）1级兵就是配置的基础值，2级兵就是金币基础数*2，3级兵就是金币基础数*3


需求V3.4.1 关于战斗过程中获取金币的表现

1.在获取金币时，需要在界面上有个表现，具体的逻辑是：
当触发金币获得时，ReplicatedStorage - CoinNumShow - CoinNumShow是一个textlabel，需要复制一份出来，然后在玩家界面上中间部分随机范围内，做一个出现然后在屏幕上抛物线炸开，然后消失的过程
这是一个用来告诉玩家你获得了金币的表现。每次战斗过程中触发了金币获得吗，就做一个这个抛洒，每次抛洒力度方向范围都随机，看起来像是烟花不断炸开

2.ReplicatedStorage - CoinNumShow - CoinNumShow的visible属性是false，复制出来后要改成true
3.ReplicatedStorage - CoinNumShow - CoinNumShow是textlabel，复制出来要改成本次获得的金币的数值，格式是xxx$

需求V3.5 新手引导

概述：我们在游戏中需要加入新手引导逻辑，主要是用于引导玩家前往目的地去触发一些操作

详细规则：
我们暂时只做两类新手引导：
1.引导玩家前往兵种商店
2.引导玩家前往挂机奖励领取邮箱

具体引导表现：
在游戏中，Workspace - Effect这个文件夹下有一个叫Guide01的part，还有一个叫Guide02的part，这两个part是用于承载一段指引beam的两个part
当出现引导时，就需要复制一份Guide01，绑定到玩家的躯干上，复制一份Guide02，出现在目标位置上，这样形成一份引导箭头
当玩家距离Guide02小于一定距离时，就移除Guide02与Guide02
注意生成引导时，Guide01和Guide02下的子节点等全部内容都要复制过来不要遗漏

1.新手刚进入游戏时，在玩家身上和该玩家家园的KeepShoper01之间建立引导，引导玩家前往目的地
2.当玩家登录游戏，并且玩家的挂离线金币数大于等于0时，在玩家和玩家家园的Mail之间建立引导

这两个引导都需要做数据保存，当引导生成过并且靠玩家移动到目的地从而隐藏了引导后，这两个引导以后就都不再触发了

结构要支持如果后续添加了新的引导，版本更新后新增的引导也能够正确触发


GM
我要求要有gm命令能直接让我测试引导，并且可以清除我的引导记录方便再次进来时触发引导


需求文档V3.6

概述：我们需要加一个挑战过程中玩家的关卡进度的实时表现

详细规则：
1.在游戏中，角色的兵种总是从当前章节第一关往最后一关依次打过去，所以挑战是一个线性的过程，我们需要把整个挑战过程的进度给表现出来
2.具体进度计算规则是：
    1）以玩家家里的IdleFloor为起点，根据我们配置的本章节的总关卡数，可以算出来本章节有多少个小关卡节点
    2）最后一关的关卡地图里面的IdleFloor就是终点

3.StarterGui - Distance - Bg - ProgressBg是一个Frame，代表整个关卡的总长度是1
4.StarterGui - Distance - Bg - ProgressBg - PlayerIcon是玩家的头像，需要把这个PlayerIcon的图片资源换成玩家的头像，头像的位置代表玩家当前的进度比例
5.玩家初始位置是{0, 0},{0.5, 0}，Y轴坐标不动，只看X轴，用Scale，X坐标是0就代表玩家在起点
6.随着关卡不断深入，玩家的位置不断向前，打到最后一关时，X坐标就变成1
7.进度就以战场中心变化即可，比如一共10关，从第一关到第二关的过程中，玩家的头像坐标就是线性丝滑从0变到0.1，打完后前往第二关时就丝滑从0.1变到0.2，随着兵种移动，头像也跟着移动，看起来要是同步的

8.关于表现是：当玩家点了attack按钮开始战斗后，立刻把StarterGui - Distance - Bg的visible属性改成true，然后执行位置计算逻辑，当战斗结束弹出结算界面后，再把StarterGui - Distance - Bg的visible属性改成false


需求文档V3.7  章节关卡地图替换

概述：关于关卡替换的逻辑，我希望不同章节会有不同的挑战地图，主要就是ReplicatedStorage - StageTemplate下面的不同的关卡模型，比如StageTemplate下的Style01和Style02是两种不同风格关卡地图

详细规则：
1.我们当前的关卡是分章节的，具体结构是，每个章节，下面有多个关卡
2.现在所有关卡都统一使用的是ReplicatedStorage - StageTemplate - Style01下的关卡模型资源，但是我其实开发了多套不同资源

3.我的需求是：给每个章节都配置一个关卡模板，比如章节下的关卡模板填Style01，就代表关卡生成时是去复制ReplicatedStorage - StageTemplate - Style01下的资源，比如第一章打完该打第二章的时候，关卡模板填的Style02，就代表去复制ReplicatedStorage - StageTemplate - Style02的关卡资源
4.每个Style0X下的结构都是一样的，都包含StageEnd和StageMiddle

我们这个版本暂时就给第一章用Style01，第二章用Style02

这个数据是要保存的，比如玩家打完了第一章，后面就一直是挑战第二章，打完第二章就是打第三章


需求文档V3.8 音效逻辑

概述：游戏内需要音效系统，在各个场景下需要播放对应的音效

详细需求：

1.游戏内通用BGM：在打开游戏加载完成后，需要播放系统默认背景音效，资源路径是SoundService - BGM - Home - Road To War (Underscore Version)，这个音效的资源id是rbxassetid://1842908030，背景音效在非战斗状态下始终默认循环播放即可
2.战斗bgm:在玩家点击了攻击按钮开始进攻后，关闭游戏通用BGM的播放，转而改成播放战斗bgm，路径是SoundService - BGM - Battle - Urban Racer (Alt Vs)，资源id是rbxassetid://1838627590，关闭战斗后关闭战斗bgm的播放，转而播放通用bgm即可

3.在玩家领取离线金币时，播放一次性音效，路径是：SoundService - Audio - Common - CoinsTrigger，资源id是rbxassetid://99023919906775
4.在战斗结束后，弹出胜利结算界面时，播放一次性音效：SoundService - Audio - Common - Victory royale，资源id是rbxassetid://5205229311，在播放的过程中如果玩家点击了confirm按钮，则立刻关闭该音效的播放

5.在兵种合成时，播放音效播放一次性音效：SoundService - Audio - Common - Merge，资源id是rbxassetid://7393525156
6.当玩家购买道具但是金币不如时，播放一次性音效：SoundService - Audio - Common - Error Sound 1，资源id是：rbxassetid://8400918001


需求文档V3.9
替换房屋时的逻辑表现：

1.我们在通过某些章节后会替换我们的房屋，但是目前没有表现，我希望我们加入正确的表现
具体的表现逻辑是：
1.房屋升级时，一定是玩家通过了某一章的最后一关，此时一定会弹出胜利弹框
2.当玩家点击了胜利弹框关闭界面，玩家重生在基地时，现在是直接替换了房屋，我要求改成：先不要替换，然后镜头拉高，看着房屋，然后等待1秒后，当前等级的房屋消失，然后新的房屋出现，出现后，再等待1秒后，镜头解除，恢复常规镜头


需求文档V3.9.1

1.补充一个新的引导：当玩家到达了商店后，通过任意渠道获得第一个兵种时，在玩家身上和玩家基地的idleFloor的中心位置也出现引导线，表现逻辑和之前两个已经完成的引导一样，也是玩家到达目的地后引导消失

2.补充一个引导表现逻辑：关于聚焦一个按钮表现的，基本逻辑是：
    1）.获取目标ui的位置，然后系统自动在这个ui的上下左右分别生成4个黑色半透明Frame，看起来正好把这个目标ui给包住，唯独把目标亮起来
    2）所以我们目前的引导其实是有两种表现方式：第一种是用引导线引导玩家到目的地，另一种是用半透明Frame把玩家要点的按钮给包起来

3.我们要实行第二种表现的引导共2次：
    1）玩家到达idleFloor的目标点后，此时引导beam消失，然后背包中有小兵，就用frame把背包ui框起来，玩家点击了背包中的任意一个小兵后，移除这个引导Frame；需要注意的是：玩家要是在到达目的地时，背包中没有任何兵，就跳过本次引导展示并视为已经完成

    2）当玩家第一次有任意兵摆放在家里的idlefloor上时，用frame把Attack按钮包起来，点击后消失并视为这一次引导完成

4.用半透明Frame包起来目标ui的时候，给Frame做一个出现动效，比如是右边的frame，就从屏幕右边向左边划出，比如下面的Frame就从屏幕下面向上面划出，看起来有个聚焦的过程

5.所以我们目前的引导总共总结起来就是下面这些：
    1）进入游戏后引导玩家前往商店（beam）
    2）购买任意兵种后前往idleFloor中心（beam）
    3）引导点击背包中的任意兵种（半透明Frame包起来）
    4）引导点击Attack按钮（半透明Frame包起来）
    5）玩家离线后再上线引导领取挂机金币

需求文档V3.9.2

新增战斗力系统：

1.我们定义一个战斗力公式：战斗力 (CP) = (HP * 0.15) + (DPS * 2) + (射程 * 2)，注意其中DPS的计算方式是 DPS=攻击力/攻击速度
2.每个兵都有以上这些属性，所以这些兵都能得出一个战斗力值
3.玩家的总战斗力就是玩家当前拥有的所有兵的总战斗力之和，不论是否摆放在地板上，战斗力都是总的战斗力

4.关于玩家的战斗力显示：
    1）每个玩家的家园中，都有一个专属自己的一个模型叫Information
    2）Information这个模型节点下有个叫Part的Part，其中Part下分别挂载了一个叫SurfaceGui01和SurfaceGui02的SurfaceGui，二者子结构完全相同
    3）以Surface01举例，在Surface01下有个叫Frame的Frame，其下有一个叫PlayerName的子节点，PlayerName也有个子节点叫Name，这是一个textlabel，用于显示玩家名字，Frame下还有个和PlayerName同层级的子节点叫PlayerPower，PlayerPower也有个子节点叫Num，这个用于显示玩家的战斗力总和
    4）Surface02和Surface01一样的结构，显示的内容也要同步一致
    5）界面上显示的玩家战斗力要实时根据玩家的战斗力变化而变化，要保持及时更新

5.当玩家两个兵合成一个新的兵后，战斗力要重新计算，也就是移除原来的两个兵的战斗力，再加入新的出现的更高等级的兵的战斗力



需求文档V4.2  兵种信息显示

1.在我们的游戏中，兵种是有攻击力/血量这些属性的，但是兵种放在地上后看不到这些属性，我们需要提供一个这样的功能
2.我希望在游戏中，玩家点击一下（注意是就点击一下），立刻弹出这个兵当前的属性面板，然后点击任意空白区域就关闭这个属性面板
3.在属性面板出现的情况下，玩家任意点击其他按钮或者屏幕任何地方，都立刻关闭面板
4.属性面板模板是：StarterGui - TipsRole - TipsBg，把TipsBg的Visible属性改成True就是显示出来，将Visible属性改成False就是关闭
5.TipsBg - IconBg - Icon是一个imagelabel，用于显示兵的头像
6.TipsBg - ATK用于显示这个兵当前的攻击力数值，TipsBg - HP用于显示血量数值，TipsBg - Name用于显示兵种名字，TipsBg - Quality显示品质，这里与兵种商店逻辑一样，TipsBg - Range显示是近战还是远程，也就是配置中的Range或者Melee，TipsBg - Level用于显示等级数值，格式是Lv.X 


需求文档V4.3  系统提示词

1.当玩家购买商店内道具时，如果金币不足，需要提示英文文本：Not enough cash
2.当玩家购买商店内道具时，如果库存不足，需要提示英文文本：Out of stock
3.提示词显示使用StarterGui - TipsSystem - Frame - ErrorText，将ErrorText的Text设置为对应文本，并把Frame.Visible改为True
4.Frame出现时需要有小动效：从屏幕中间位置浮动到Frame的目标位置（{0.5, 0}, {0.2, 0}），整体持续约1秒后自动隐藏
5.提示词未消失前再次触发时，立即隐藏上一条提示并重新播放新的提示动画
6.需要防止连续快速点击造成提示堆叠或异常（仅保留最新一次提示）
7.库存不足时点击购买也要播放错误提示音效（与金币不足相同）

需求文档V4.4 徽章系统

1.我们用roblox内置的徽章系统，我们已经在后台创建好了两个徽章：1068309156030736与1363005461717615以及4053364769846356
2.徽章系统后期要支持拓展新的徽章，当前我们就只做3个徽章的发放
3.徽章1：Welcome，id是：1068309156030736，获得条件是：新玩家进入游戏后立刻为玩家发放这个徽章，上线后老玩家进入游戏时，需要检测，如果玩家没这个徽章，也要发放这个徽章
4.徽章2：战力值达到3000以上，id是：1363005461717615，条件是玩家战力值达到3000+时，为玩家发放这个徽章，同样的，玩家上线时检测玩家如果战力值达到条件了但是没这个徽章也要自动发放
5.徽章3：战力值达到50000以上，Id是：4053364769846356，条件是玩家战力值达到50000+时，为玩家发放徽章，同样的，玩家上线时检测玩家如果战力值达到条件了但是没这个徽章也要自动发放