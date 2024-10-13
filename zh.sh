#!/bin/sh

sed -i "s|'Listening for HTTP requests on port '|'监听HTTP请求的端口 '|g" ztncui/src/bin/www
sed -i "s|' on all interfaces'|' 在所有接口上'|g" ztncui/src/bin/www
sed -i "s|' on localhost'|' 在本地主机'|g" ztncui/src/bin/www
sed -i "s|'Listening for HTTPS requests on port '|'监听HTTPS请求的端口 '|g" ztncui/src/bin/www
sed -i "s|' on address '|' 在地址 '|g" ztncui/src/bin/www
sed -i "s|' require elevated privileges');|' 需要更高的权限');|g" ztncui/src/bin/www
sed -i "s|' already in use');|' 已经被使用了');|g" ztncui/src/bin/www
sed -i "s|'Listening on '|'监听于 '|g" ztncui/src/bin/www

sed -i "s|('cannot find user')|('找不到用户')|g" ztncui/src/controllers/auth.js
sed -i "s|('invalid password')|('密码无效')|g" ztncui/src/controllers/auth.js
sed -i "s|'Access denied\!';|'拒绝访问\!';|g" ztncui/src/controllers/auth.js

sed -i "s|'Gateway must be a valid IPv4 or IPv6 address'|'网关必须是有效的IPv4或IPv6地址'|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'v4AssignMode',|title: 'IPv4分配模式',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'v6AssignMode',|title: 'IPv6分配模式',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'dns',|title: 'DNS',|g" ztncui/src/controllers/networkController.js
sed -i "s|(\"Error renaming network \"|(\"重命名网络时出错 \"|g" ztncui/src/controllers/networkController.js
sed -i "s|(\"network name validation errors\",|(\"网络名称验证错误\",|g" ztncui/src/controllers/networkController.js
sed -i "s|+ ' of network '|+ ' 从网络 '|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'activeBridge state must be boolean')|, '活动网桥状态必须为布尔值')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Authorization state must be boolean')|, '授权状态必须为布尔值')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'End of IP assignment pool is required')|, 'IP分配池结束地址是必需的')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'End of IP assignment pool must be valid IPv4 address')|, 'IP分配池结束地址必须是有效的IPv4地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP address must be a valid IPv4 or IPv6 address')|, 'IP地址必须是有效的IPv4或IPv6地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP address must fall within a managed route')|, 'IP地址必须位于托管路由内')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP address required')|, '需要IP地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP range end needs a valid IPv4 or IPv6 address')|, 'IP结束地址需要有效的IPv4或IPv6地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP range end required')|, '需要IP结束地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP range start needs a valid IPv4 or IPv6 address')|, 'IP起始地址需要有效的IPv4或IPv6地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'IP range start required')|, '需要IP起始地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Member ID is required')|, '成员ID是必需的')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Network address is required')|, '网络地址是必需的')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Network address must be in CIDR notation')|, '网络地址必须使用CIDR表示法')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Network name required')|, '需要网络名称')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Start of IP assignment pool is required')|, 'IP分配池起始地址是必需的')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Start of IP assignment pool must be valid IPv4 address')|, 'IP分配池起始地址必须是有效的IPv4地址')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Target network is required')|, '目标网络是必需的')|g" ztncui/src/controllers/networkController.js
sed -i "s|, 'Target network must be valid CIDR format')|, '目标网络必须是有效的CIDR格式')|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error adding route for network '|error: '为网络添加路由时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error applying IP Assignment Pools for network '|error: '应用IP分配池时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error applying private for network '|error: '应用专用网络时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error applying v4AssignMode for network '|error: '为网络应用V4分配模式时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error applying v6AssignMode for network '|error: '为网络应用V6分配模式时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error creating network '|error: '创建网络时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error deleting IP Assignment Pool for network '|error: '删除网络的IP分配池时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error deleting network '|error: '删除网络时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error deleting route for network '|error: '删除网络的路由时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'ERROR getting ZT status: '|error: '获取Zerotier状态时出错: '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error resolving detail for member '|error: '解析成员的详细信息时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error resolving detail for network '|error: '解析网络的详细信息时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error resolving network '|error: '解析网络时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error resolving network detail for network '|error: '解析网络的网络详细信息时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error resolving network detail'|error: '解析网络详细信息时出错'|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error retrieving list of networks on this controller: '|error: '检索此控制器上的网络列表时出错: '|g" ztncui/src/controllers/networkController.js
sed -i "s|error: 'Error updating dns for network '|error: '更新网络的dns时出错 '|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Create Network - error',|title: '创建网络 - 错误',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Create network',|title: '创建网络',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Create Network',|title: '创建网络',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Delete member from '|title: '删除成员从 '|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Delete member from network',|title: '从网络中删除成员',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Delete network',|title: '删除网络',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Detail for network',|title: '网络详细信息',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'dns',|'ZTNCUI控制器'|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Easy setup of network',|title: '网络的简易设置',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'ipAssignmentPools',|title: 'IP分配池',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'ipAssignments '|title: 'IP分配 '|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Network '|title: '网络 '|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Network member detail',|title: '网络成员详细信息',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'Networks on this controller',|title: '此控制器上的网络',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'private',|title: '私有',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'routes',|title: '路由',|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'ztncui',|title: 'ZTNCUI控制器',|g" ztncui/src/controllers/networkController.js
sed -i "s|'Network setup succeeded'|'网络设置成功'|g" ztncui/src/controllers/networkController.js
sed -i "s|title: 'ipAssignments',|title: 'IP分配',|g" ztncui/src/controllers/networkController.js

sed -i "s|title: 'Admin users',|title: '管理员',|g" ztncui/src/controllers/usersController.js
sed -i "s|'List of users with admin priviledges',|'列出具有管理员权限的用户列表',|g" ztncui/src/controllers/usersController.js
sed -i "s|message: 'Error',|message: '错误',|g" ztncui/src/controllers/usersController.js
sed -i "s|error: 'Error returning list of users: '|error: '返回用户列表时出错: '|g" ztncui/src/controllers/usersController.js
sed -i "s|title: 'Set password',|title: '设置密码',|g" ztncui/src/controllers/usersController.js
sed -i "s|, 'Username required')|, '需要用户名')|g" ztncui/src/controllers/usersController.js
sed -i "s|, 'Password required')|, '需要密码')|g" ztncui/src/controllers/usersController.js
sed -i "s|, 'Minimum password length is '|, '最小密码长度为 '|g" ztncui/src/controllers/usersController.js
sed -i "s|, 'Please re-enter password')|, '请重新输入密码')|g" ztncui/src/controllers/usersController.js
sed -i "s|' characters')|' 字符')|g" ztncui/src/controllers/usersController.js
sed -i "s|, 'Passwords are not the same')|, '两次输入密码不一样')|g" ztncui/src/controllers/usersController.js
sed -i "s|'Please check errors below';|'请检查下面的错误';|g" ztncui/src/controllers/usersController.js
sed -i "s|'Successfully set password for '|'已成功设置密码为用户 '|g" ztncui/src/controllers/usersController.js
sed -i "s|title: 'Create new admin user',|title: '创建新的管理员用户',|g" ztncui/src/controllers/usersController.js
sed -i "s|title: 'Delete user',|title: '删除用户',|g" ztncui/src/controllers/usersController.js

sed -i "s|('Cannot delete non-existent route target');|('无法删除不存在的路由目标');|g" ztncui/src/controllers/zt.js
sed -i "s|('Route target is not unique');|('路由目标不是唯一的');|g" ztncui/src/controllers/zt.js

sed -i "s|{title: 'ztncui'});|{title: 'ZTNCUI控制器'});|g" ztncui/src/routes/index.js
sed -i "s|'Access denied\!')|'拒绝访问\!')|g" ztncui/src/routes/index.js
sed -i "s|title: 'Login',|title: '登录',|g" ztncui/src/routes/index.js
sed -i "s|'Authenticated as '|'认证成功，用户为 '|g" ztncui/src/routes/index.js
sed -i "s|'Authentication failed, please check your username and password.'|'身份验证失败，请检查您的用户名和密码.'|g" ztncui/src/routes/index.js

sed -i "s|'Home',|'主页',|g" ztncui/src/views/controller_layout.pug
sed -i "s|'Users',|'用户',|g" ztncui/src/views/controller_layout.pug
sed -i "s|'Networks',|'网络',|g" ztncui/src/views/controller_layout.pug
sed -i "s|'Add network',|'添加网络',|g" ztncui/src/views/controller_layout.pug

sed -i "s|b No DNS configuration on this network.|b 该网络未配置DNS.|g" ztncui/src/views/dns.pug
sed -i "s|Domain:|域名:|g" ztncui/src/views/dns.pug
sed -i "s|Servers:|DNS服务器:|g" ztncui/src/views/dns.pug
sed -i "s|h3 Change DNS configuration:|h3 更改DNS配置:|g" ztncui/src/views/dns.pug
sed -i "s|'(one IP address per line)')|'(每行一个IP地址)')|g" ztncui/src/views/dns.pug
sed -i "s|) Submit|) 提交|g" ztncui/src/views/dns.pug
sed -i "s|) Cancel|) 取消|g" ztncui/src/views/dns.pug

sed -i "s|network controller UI|网络控制器用户界面|g" ztncui/src/views/front_door.pug

sed -i "s|Logout|注销|g" ztncui/src/views/head_layout.pug
sed -i "s|network controller UI by|网络控制器用户界面汉化|g" ztncui/src/views/index.pug
sed -i "s|a(href='https://key-networks.com' target='_blank') Key Networks|a(href='https://github.com/chenxudong2020/docker-zerotier-planet' target='_blank') |g" ztncui/src/views/index.pug
sed -i "s|This network controller has a ZeroTier address of|该控制器的ZeroTier地址为|g" ztncui/src/views/index.pug
sed -i "s|ZeroTier version|ZeroTier版本为|g" ztncui/src/views/index.pug
sed -i "s|List all networks on this network controller|列出该网络控制器上的所有网络|g" ztncui/src/views/index.pug

sed -i "s|th IP range start|th IP开始范围|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|th IP range end|th IP结束范围|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|Add new IP Assignment Pool:|添加新的IP分配池:|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|IP range start:|IP开始范围:|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|'IP range start'|'IP开始范围'|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|IP range end:|IP结束范围:|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|'IP range end'|'IP结束范围'|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|) Submit|) 提交|g" ztncui/src/views/ipAssignmentPools.pug
sed -i "s|) Cancel|) 取消|g" ztncui/src/views/ipAssignmentPools.pug

sed -i "s|Note errors listed below|注意下面列出的错误|g" ztncui/src/views/ipAssignments.pug
sed -i "s|Member name:|成员名称:|g" ztncui/src/views/ipAssignments.pug
sed -i "s|ZeroTier address:|ZeroTier地址:|g" ztncui/src/views/ipAssignments.pug
sed -i "s|th IP address|th IP地址|g" ztncui/src/views/ipAssignments.pug
sed -i "s|Managed routes|管理路由|g" ztncui/src/views/ipAssignments.pug
sed -i "s|th Target|th 目标|g" ztncui/src/views/ipAssignments.pug
sed -i "s|th Gateway|th 网关|g" ztncui/src/views/ipAssignments.pug


sed -i "s|Username:|用户名:|g" ztncui/src/views/login.pug
sed -i "s|'Enter your username'|'输入你的用户名'|g" ztncui/src/views/login.pug
sed -i "s|Password:|密码:|g" ztncui/src/views/login.pug
sed -i "s|'Enter your password'|'输入你的密码'|g" ztncui/src/views/login.pug
sed -i "s|) Login|) 登录|g" ztncui/src/views/login.pug
sed -i "s|) Cancel|) 取消|g" ztncui/src/views/login.pug

sed -i "s|Login|登录|g" ztncui/src/views/login_layout.pug

sed -i "s|was deleted|已被删除|g" ztncui/src/views/member_delete.pug
sed -i "s|) Members|) 成员|g" ztncui/src/views/member_delete.pug
sed -i "s|To undo a member deletion, just get the member to join the network again.|想要撤销删除成员，仅需要将该成员再一次加入网络.|g" ztncui/src/views/member_delete.pug
sed -i "s|After deleting a member, you may see them appear in the list of members again.  This is a ZeroTier issue.  Just get the user to leave the network.|删除成员后，你可能会再次看到它们出现在成员列表中。这是ZeroTier的问题。只需让用户离开网络即可。|g" ztncui/src/views/member_delete.pug
sed -i "s|) Delete|) 删除|g" ztncui/src/views/member_delete.pug
sed -i "s|) Cancel|) 取消|g" ztncui/src/views/member_delete.pug

sed -i "s|for member|成员|g" ztncui/src/views/member_detail.pug
sed -i "s|in network|在网络中|g" ztncui/src/views/member_detail.pug
sed -i "s|Members|成员|g" ztncui/src/views/member_detail.pug

sed -i "s|Network name:|网络名称:|g" ztncui/src/views/network_create.pug
sed -i "s|'Enter new network name'|'输入新的网络名称'|g" ztncui/src/views/network_create.pug
sed -i "s|Create Network|创建网络|g" ztncui/src/views/network_create.pug

sed -i "s|was deleted|已被删除|g" ztncui/src/views/network_delete.pug
sed -i "s|Warning\! Deleting a network cannot be undone|警告\! 删除网络操作无法撤销|g" ztncui/src/views/network_delete.pug
sed -i "s|) Delete|) 删除|g" ztncui/src/views/network_delete.pug
sed -i "s|) Cancel|) 取消|g" ztncui/src/views/network_delete.pug

sed -i "s| Network | 网络 |g" ztncui/src/views/network_detail.pug
sed -i "s|"Private" : "Public"|"私有" : "公共"|g" ztncui/src/views/network_detail.pug
sed -i "s|Easy setup|简易设置|g" ztncui/src/views/network_detail.pug
sed -i "s|) Routes|) 路由|g" ztncui/src/views/network_detail.pug
sed -i "s|Assignment Pools|IP分配池|g" ztncui/src/views/network_detail.pug
sed -i "s|IPv4 Assign Mode|IPv4分配模式|g" ztncui/src/views/network_detail.pug
sed -i "s|IPv6 Assign Mode|IPv6分配模式|g" ztncui/src/views/network_detail.pug
sed -i "s|Members (|成员 (|g" ztncui/src/views/network_detail.pug
sed -i "s|Member name|成员名称|g" ztncui/src/views/network_detail.pug
sed -i "s|Member ID|成员ID|g" ztncui/src/views/network_detail.pug
sed -i "s|Authorized|已授权|g" ztncui/src/views/network_detail.pug
sed -i "s|Active bridge|主动桥接|g" ztncui/src/views/network_detail.pug
sed -i "s|IP assignment|IP分配|g" ztncui/src/views/network_detail.pug
sed -i "s|Peer status|节点状态|g" ztncui/src/views/network_detail.pug
sed -i "s|Peer address / latency|节点地址/延迟|g" ztncui/src/views/network_detail.pug
sed -i "s|ONLINE|在线|g" ztncui/src/views/network_detail.pug
sed -i "s|RELAY|转发|g" ztncui/src/views/network_detail.pug
sed -i "s|CONTROLLER|控制器|g" ztncui/src/views/network_detail.pug
sed -i "s|OFFLINE|离线|g" ztncui/src/views/network_detail.pug
sed -i "s|There are no members on this network - invite users to join|这个网络上没有成员 - 邀请用户加入|g" ztncui/src/views/network_detail.pug
sed -i "s|Refresh|刷新|g" ztncui/src/views/network_detail.pug
sed -i "s|Detail for network|网络详细信息|g" ztncui/src/views/network_detail.pug
sed -i "s|) Networks|) 网络|g" ztncui/src/views/network_detail.pug

sed -i "s|'Invalid network CIDR';|'网络 CIDR 不可用';|g" ztncui/src/views/network_easy.pug
sed -i "s|Help|帮助|g" ztncui/src/views/network_easy.pug
sed -i "s|Please note that this utility only supports IPv4 at this stage.|请注意，此应用程序在此阶段仅支持IPv。|g" ztncui/src/views/network_easy.pug
sed -i "s|Use the following button to automatically generate a random network address, otherwise fill in the network address CIDR manually and the IP assignment pool will be automatically calculated for you.  You can manually alter these calculated values.|使用以下按钮可自动生成随机网络地址，否则请手动填写网络地址 CIDR，IP 分配池将为您自动计算。 您可以手动更改这些计算值。|g" ztncui/src/views/network_easy.pug
sed -i "s|Generate network address|生成网络地址|g" ztncui/src/views/network_easy.pug
sed -i "s|Network address in CIDR notation|以 CIDR 表示的网络地址|g" ztncui/src/views/network_easy.pug
sed -i "s|'e.g. 10.11.12.0/24'|'示例 10.11.12.0/24'|g" ztncui/src/views/network_easy.pug
sed -i "s|Start of IP assignment pool|IP分配池起始于|g" ztncui/src/views/network_easy.pug
sed -i "s|'e.g. 10.11.12.1'|'示例 10.11.12.1'|g" ztncui/src/views/network_easy.pug
sed -i "s|End of IP assignment pool|IP分配池于|g" ztncui/src/views/network_easy.pug
sed -i "s|'e.g. 10.11.12.254'|'示例 10.11.12.254'|g" ztncui/src/views/network_easy.pug
sed -i "s|Submit|提交|g" ztncui/src/views/network_easy.pug
sed -i "s|Cancel|取消|g" ztncui/src/views/network_easy.pug

sed -i "s| Network | 网络 |g" ztncui/src/views/network_layout.pug
sed -i "s|Back|返回|g" ztncui/src/views/network_layout.pug

sed -i "s|Network name|网络名称|g" ztncui/src/views/networks.pug
sed -i "s|Network ID|网络ID|g" ztncui/src/views/networks.pug
sed -i "s|) detail|) 详细信息|g" ztncui/src/views/networks.pug
sed -i "s|easy setup|简易设置|g" ztncui/src/views/networks.pug
sed -i "s|) members|) 成员|g" ztncui/src/views/networks.pug
sed -i "s|There are no networks on this network controller - click \"Add network\" above to create a new network.|该网络控制器上没有网络 - 点击上面的\"添加网络\"创建新网络。|g" ztncui/src/views/networks.pug

sed -i "s|for member|成员|g" ztncui/src/views/not_implemented.pug
sed -i "s|Editing of|编辑|g" ztncui/src/views/not_implemented.pug
sed -i "s|has not been implemented.|尚未完成。|g" ztncui/src/views/not_implemented.pug
sed -i "s|Note that you may be able to edit some properties on the |请注意，你还可以编辑 |g" ztncui/src/views/not_implemented.pug
sed -i "s|Members|其他|g" ztncui/src/views/not_implemented.pug
sed -i "s|page.|页。|g" ztncui/src/views/not_implemented.pug

sed -i "s|Username:|用户名:|g" ztncui/src/views/password.pug
sed -i "s|'Enter username'|'输入用户名'|g" ztncui/src/views/password.pug
sed -i "s|Enter new password:|输入新密码:|g" ztncui/src/views/password.pug
sed -i "s|'Enter new password'|'输入新密码'|g" ztncui/src/views/password.pug
sed -i "s|Re-enter password:|再次输入密码:|g" ztncui/src/views/password.pug
sed -i "s|'Re-enter password'|'再次输入密码'|g" ztncui/src/views/password.pug
sed -i "s|Change password on next login:|下次登录后更改密码:|g" ztncui/src/views/password.pug
sed -i "s|Set password|设置密码|g" ztncui/src/views/password.pug
sed -i "s|Cancel|取消|g" ztncui/src/views/password.pug

sed -i "s|Enable access control.  Warning: if you disable this, you will not be able to de-authorize members of the network.  Disable this only if you know what you are doing.|启用访问控制。警告:如果禁用此功能，将无法取消对网络成员的授权。只有在知道自己在做什么的情况下才能禁用。|g" ztncui/src/views/private.pug

sed -i "s|th Target|th 目标|g" ztncui/src/views/routes.pug
sed -i "s|th Gateway|th 网关|g" ztncui/src/views/routes.pug
sed -i "s|Add new route:|添加新路由|g" ztncui/src/views/routes.pug
sed -i "s|Target:|目标:|g" ztncui/src/views/routes.pug
sed -i "s|'e.g. 10.11.12.0/24'|'示例 10.11.12.0/24'|g" ztncui/src/views/routes.pug
sed -i "s|Gateway:|网关:|g" ztncui/src/views/routes.pug
sed -i "s|'e.g. 172.16.2.1 or leave blank if the target is the ZT network'|'示例 172.16.2.1 如果目标是ZeroTier网络，则留空'|g" ztncui/src/views/routes.pug
sed -i "s|Submit|提交|g" ztncui/src/views/routes.pug
sed -i "s|Cancel|取消|g" ztncui/src/views/routes.pug

sed -i "s|No such user|没有该用户|g" ztncui/src/views/user_delete.pug
sed -i "s|You may not delete yourself|你不能删除自己|g" ztncui/src/views/user_delete.pug
sed -i "s|was deleted|已被删除|g" ztncui/src/views/user_delete.pug
sed -i "s|Warning\! Deleting a user cannot be undone|警告\!删除用户操作无法撤销|g" ztncui/src/views/user_delete.pug
sed -i "s|Delete|删除|g" ztncui/src/views/user_delete.pug
sed -i "s|Cancel|取消|g" ztncui/src/views/user_delete.pug

sed -i "s|set password|设置密码|g" ztncui/src/views/users.pug
sed -i "s|There are no users on this system|该系统没有用户|g" ztncui/src/views/users.pug

sed -i "s|'Home',|'主页',|g" ztncui/src/views/users_layout.pug
sed -i "s|'Users',|'用户',|g" ztncui/src/views/users_layout.pug
sed -i "s|'Networks',|'网络',|g" ztncui/src/views/users_layout.pug
sed -i "s|'Create user',|'创建用户',|g" ztncui/src/views/users_layout.pug

sed -i "s|Auto-assign from IP Assignment Pool|从IP分配池自动分配|g" ztncui/src/views/v4AssignMode.pug

sed -i "s|ZT 6plane (/80 routable for each device)|ZeroTier 6PLANE(每个设备 /80 可路由)|g" ztncui/src/views/v6AssignMode.pug
sed -i "s|ZT rfc4193 (/128 for each device)|ZeroTier RFC4193（每个设备 /128）|g" ztncui/src/views/v6AssignMode.pug
sed -i "s|Auto-assign from IP Assignment Pool|从IP分配池自动分配|g" ztncui/src/views/v6AssignMode.pug
