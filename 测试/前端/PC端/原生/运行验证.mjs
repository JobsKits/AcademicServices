import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, cp, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import net from 'node:net';

const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const pc=path.join(root,'代码/前端/PC端');
const backend=path.join(root,'代码/后端/后端代码');
const work=await mkdtemp(path.join(tmpdir(),'zhixu-native-contract-'));
const run=(cmd,args,options={})=>new Promise((resolve,reject)=>{
  const process=spawn(cmd,args,{stdio:'inherit',...options});
  process.on('error',reject);
  process.on('exit',(code,signal)=>code===0?resolve():reject(new Error(`${cmd} failed (${code??signal})`)));
});
const xml=s=>s.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
const probe=net.createServer();
await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
const port=probe.address().port;
await new Promise(resolve=>probe.close(resolve));
const binary=path.join(work,process.platform==='win32'?'server.exe':'server');
await run(process.env.GO_BIN??'go',['build','-o',binary,'./cmd/server'],{cwd:backend});
const server=spawn(binary,[],{cwd:backend,stdio:['ignore','pipe','pipe'],env:{...process.env,APP_ENV:'test',DEMO_MODE:'1',DEMO_CUSTOMER_PASSWORD:'demo-customer',DATABASE_URL:'',DATA_DIR:path.join(work,'data'),LISTEN_ADDR:`127.0.0.1:${port}`}});
let output='';server.stdout.on('data',b=>output+=b);server.stderr.on('data',b=>output+=b);
const cleanup=()=>{if(server.exitCode===null)server.kill('SIGTERM');};
process.on('SIGINT',cleanup);process.on('SIGTERM',cleanup);
try{
  let ready=false;
  for(let i=0;i<100;i++){
    if(server.exitCode!==null)throw new Error('Temporary server failed: '+output);
    try{const response=await fetch(`http://127.0.0.1:${port}/api/v1/products`);if(response.ok){ready=true;break;}}catch{}
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  if(!ready)throw new Error('Temporary server did not become ready');
  const base=`http://127.0.0.1:${port}/api/v1`;
  const web=await fetch(`http://127.0.0.1:${port}/client/`).then(r=>r.text());
  if(!web.includes('src="shop.js"'))throw new Error('Go /client/ did not serve the standard Web');
  if(process.platform==='darwin'){
    const swift=path.join(work,'swift');await mkdir(swift);
    for(const file of ['shop_strings.json','products.json'])await cp(path.join(pc,'Web/Assets',file),path.join(swift,file));
    await run('xcrun',['swiftc','-parse-as-library','-swift-version','5',path.join(pc,'MacOS/Sources/Models.swift'),path.join(pc,'MacOS/Sources/LocalDemoAuth.swift'),path.join(pc,'MacOS/Sources/ShopStore.swift'),path.join(here,'StoreSmoke.swift'),'-o',path.join(swift,'StoreSmoke')]);
    await run(path.join(swift,'StoreSmoke'),[base]);
  }
  const csharp=path.join(work,'csharp');await mkdir(csharp);
  const project=`<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net11.0</TargetFramework><Nullable>enable</Nullable><ImplicitUsings>enable</ImplicitUsings></PropertyGroup><ItemGroup><Compile Include="${xml(path.join(pc,'Windows/ShopStore.cs'))}"/><Compile Include="${xml(path.join(pc,'Windows/LocalDemoAuth.cs'))}"/><Compile Include="${xml(path.join(here,'StoreSmoke.cs'))}"/><Content Include="${xml(path.join(pc,'Web/Assets/*.json'))}" Link="Assets/%(Filename)%(Extension)" CopyToOutputDirectory="PreserveNewest"/></ItemGroup></Project>`;
  await writeFile(path.join(csharp,'Smoke.csproj'),project);
  await run('dotnet',['run','--project',path.join(csharp,'Smoke.csproj'),'--',base]);
  console.log('PASS native stores and actual Go /client/ route. Isolated fixture retained at '+work);
}finally{
  cleanup();
  process.off('SIGINT',cleanup);process.off('SIGTERM',cleanup);
}
