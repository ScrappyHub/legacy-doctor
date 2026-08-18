"use client";

import { useMemo, useState } from "react";

type Device = { id:string; name:string; kind:string; connection:string; location:string; capacity:string; used:number; contents:string; status:"Ready"|"Needs attention"|"Waiting for media"|"Protected"; tone:"green"|"amber"|"blue" };

const devices: Device[] = [
  { id:"nvme", name:"Samsung 970 EVO Plus", kind:"NVMe SSD", connection:"NVMe", location:"Disk 3 · C:", capacity:"1.0 TB", used:94, contents:"Healthy · system disk", status:"Ready", tone:"blue" },
  { id:"g-drive", name:"Samsung 860 EVO", kind:"SATA SSD", connection:"SATA", location:"Disk 0 · G:", capacity:"1.0 TB", used:26, contents:"NTFS · healthy", status:"Ready", tone:"green" },
  { id:"s-drive", name:"ST2000DM008", kind:"SATA HDD", connection:"SATA", location:"Disk 1 · S:", capacity:"2.0 TB", used:29, contents:"NTFS · healthy", status:"Ready", tone:"green" },
  { id:"p-drive", name:"Samsung 870 QVO", kind:"SATA SSD", connection:"SATA", location:"Disk 2 · P:", capacity:"2.0 TB", used:73, contents:"NTFS · healthy", status:"Ready", tone:"green" },
  { id:"ipod", name:"Apple iPod Shuffle", kind:"MP3 player", connection:"USB", location:"Disk 4 · E:", capacity:"1.0 GB", used:1, contents:"10 files · 401,619 B · SHA-256 verified backup", status:"Protected", tone:"amber" },
  { id:"iphone", name:"Apple iPhone", kind:"Mobile device", connection:"USB · PTP", location:"USB · no drive letter expected", capacity:"—", used:0, contents:"Connected · full backup adapter not implemented", status:"Needs attention", tone:"amber" },
  { id:"optical", name:"MATSHITA DVD-RAM UJ8C0", kind:"Optical media", connection:"USB", location:"Drive D:", capacity:"—", used:0, contents:"Drive healthy · no disc inserted", status:"Waiting for media", tone:"amber" },
];
const library = [
  { label:"iPod library data", count:"8", size:"401 KB", glyph:"♫" }, { label:"Device metadata", count:"2", size:"88 B", glyph:"▣" },
  { label:"Verified backup", count:"10", size:"401,619 B", glyph:"✓" }, { label:"Visible volumes", count:"7", size:"6.0 TB", glyph:"◇" },
];
const activities = [
  { title:"iPod backup verified", meta:"10 of 10 files matched SHA-256", time:"Just now", ok:true },
  { title:"Hardware inventory", meta:"5 disks and 7 volumes discovered", time:"Just now", ok:true },
  { title:"iPod health warning", meta:"Windows reports Full Repair Needed", time:"Just now", ok:false },
];

function Icon({ name }:{ name:string }) {
  const paths:Record<string,React.ReactNode> = {
    grid:<><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></>,
    drive:<><path d="M4 6h16v12H4z"/><path d="M7 14h.01M17 14h.01"/></>, library:<><path d="M4 19V5M9 19V5M14 19V5M19 19V8"/><path d="M2 19h20"/></>,
    history:<><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/></>, shield:<><path d="M12 3 5 6v5c0 4.6 2.9 8.2 7 10 4.1-1.8 7-5.4 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/></>,
    settings:<><circle cx="12" cy="12" r="3"/><path d="M19 14.5V9.5l-2-.7-.7-1.7.9-1.9-3.5-2-1.4 1.5h-2L8.8 3.2l-3.5 2 .9 1.9-.7 1.7-2 .7v5l2 .7.7 1.7-.9 1.9 3.5 2 1.4-1.5h2l1.5 1.5 3.5-2-.9-1.9.7-1.7 2-.7Z"/></>,
  };
  return <svg viewBox="0 0 24 24" aria-hidden="true">{paths[name]}</svg>;
}

export default function Home() {
  const [selected,setSelected] = useState(devices[0]); const [query,setQuery] = useState("");
  const [notice,setNotice] = useState("Verified hardware snapshot · 2026-08-18 19:29 UTC · destructive actions disabled");
  const filtered = useMemo(()=>devices.filter(d=>`${d.name} ${d.kind} ${d.location}`.toLowerCase().includes(query.toLowerCase())),[query]);
  const gated = (action:string)=>setNotice(`${action} requires a verified restore point and explicit approval`);
  return <main className="shell">
    <aside className="sidebar"><div className="brand"><span className="brandmark">LD</span><div><strong>Legacy Doctor</strong><small>Media operations</small></div></div>
      <nav aria-label="Main navigation"><a className="active" href="#overview"><Icon name="grid"/>Overview</a><a href="#devices"><Icon name="drive"/>Devices <span>7</span></a><a href="#library"><Icon name="library"/>Library</a><a href="#recovery"><Icon name="history"/>Backups & recovery</a><a href="#protection"><Icon name="shield"/>Protection</a></nav>
      <div className="sidebar-bottom"><div className="agent"><i/><div><b>Proof mode</b><small>Real snapshot · read-only source</small></div></div><a href="#settings"><Icon name="settings"/>Settings</a></div>
    </aside>
    <section className="content"><header><div><p className="eyebrow">VERIFIED SYSTEM OVERVIEW</p><h1>Your connected legacy media.</h1><p>Real hardware evidence from this computer, with destructive actions disabled.</p></div><div className="header-actions"><button className="ghost" onClick={()=>setNotice("Latest proof snapshot · 5 disks · 7 volumes · iPod and iPhone connected")}>↻&nbsp; View scan result</button><button className="primary" onClick={()=>setNotice("The iPod backup is complete and verified; choose another device to plan its backup")}>＋&nbsp; New backup</button></div></header>
      <div className="notice"><span>●</span>{notice}<button onClick={()=>setNotice("Verified hardware snapshot · 2026-08-18 19:29 UTC · destructive actions disabled")}>×</button></div>
      <section className="metrics" id="overview"><article><div className="metric-icon green">⌁</div><div><small>CONNECTED DEVICES</small><strong>7</strong><p>5 disks · iPhone · optical</p></div></article><article><div className="metric-icon blue">◫</div><div><small>IPOD CATALOG</small><strong>10 files</strong><p>401,619 bytes hashed</p></div></article><article><div className="metric-icon purple">↺</div><div><small>VERIFIED BACKUPS</small><strong>1</strong><p>10 of 10 hashes matched</p></div></article><article><div className="metric-icon amber">△</div><div><small>NEEDS ATTENTION</small><strong>3</strong><p>iPod health · iPhone adapter · empty DVD</p></div></article></section>
      <section className="panel devices" id="devices"><div className="panel-head"><div><h2>Connected devices</h2><p>Physical media and devices currently visible to this computer.</p></div><label className="search">⌕<input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Find a device..."/></label></div>
        <div className="device-layout"><div className="device-list"><div className="table-head"><span>DEVICE</span><span>CONNECTED AT</span><span>CAPACITY</span><span>STATE</span></div>{filtered.map(device=><button key={device.id} className={`device-row ${selected.id===device.id?"selected":""}`} onClick={()=>setSelected(device)}><span className={`device-symbol ${device.tone}`}>{device.kind.includes("Mobile")?"▯":device.kind.includes("Optical")?"◉":"▰"}</span><span className="device-name"><b>{device.name}</b><small>{device.kind} · {device.connection}</small></span><span className="location"><b>{device.location}</b><small>{device.contents}</small></span><span className="capacity"><b>{device.capacity}</b>{device.used>0&&<i><em style={{width:`${device.used}%`}}/></i>}</span><span className={`status ${device.tone}`}><i/>{device.status}</span></button>)}</div>
          <aside className="device-detail"><div className="detail-top"><span className={`device-symbol large ${selected.tone}`}>▰</span><div><small>SELECTED DEVICE</small><h3>{selected.name}</h3><p>{selected.kind} · {selected.connection}</p></div></div><dl><div><dt>Visible at</dt><dd>{selected.location}</dd></div><div><dt>Contents</dt><dd>{selected.contents}</dd></div><div><dt>Protection</dt><dd>{selected.id==="ipod"?"10 files verified":"Not yet backed up"}</dd></div></dl><div className="detail-actions"><button className="primary" onClick={()=>setNotice(selected.id==="ipod"?"iPod backup already verified · 10 of 10 hashes matched":`Backup planner opened for ${selected.name}`)}>Back up now</button><button className="ghost" onClick={()=>gated("Restore")}>Restore</button></div><button className="manage" onClick={()=>setNotice(`Managing ${selected.name} in safe mode`)}>Manage device →</button></aside></div>
      </section>
      <div className="lower-grid"><section className="panel" id="library"><div className="panel-head compact"><div><h2>Unified library</h2><p>Content found across connected and backed-up devices.</p></div><button className="text-button">Open library →</button></div><div className="library-grid">{library.map(item=><button key={item.label}><span>{item.glyph}</span><div><b>{item.label}</b><small>{item.count} items · {item.size}</small></div><i>›</i></button>)}</div></section>
        <section className="panel" id="recovery"><div className="panel-head compact"><div><h2>Recent protection</h2><p>Inventories, backups, and verification receipts.</p></div><button className="text-button">View all →</button></div><div className="activity">{activities.map(a=><div key={a.title}><span className={a.ok?"ok":"warn"}>{a.ok?"✓":"!"}</span><div><b>{a.title}</b><small>{a.meta}</small></div><time>{a.time}</time></div>)}</div></section></div>
      <section className="source-strip panel"><div><p className="eyebrow">SOURCE COVERAGE</p><h2>From analog capture to modern NVMe.</h2></div><div className="source-types"><span><b>VHS</b><small>Capture adapter</small></span><span><b>iPod / MP3</b><small>File media</small></span><span><b>DVD</b><small>Optical media</small></span><span><b>ROM / COS</b><small>Legacy images</small></span><span><b>iPhone</b><small>Photo + adapter</small></span><span><b>HDD / NVMe</b><small>Block storage</small></span></div></section>
      <section className="workbench panel" id="protection"><div><p className="eyebrow">RECOVERY WORKBENCH</p><h2>Powerful actions, with guardrails.</h2><p>Every write operation is previewed, requires a verified recovery point, and produces an audit receipt.</p></div><div className="work-actions"><button onClick={()=>gated("Assign drive letter")}><b>＋</b><span>Assign drive letter<small>Repair an unmounted volume</small></span></button><button onClick={()=>gated("Format media")}><b>▦</b><span>Format media<small>Erase and prepare a device</small></span></button><button onClick={()=>gated("Disk image")}><b>◫</b><span>Create disk image<small>Sector-level preservation</small></span></button><button onClick={()=>gated("Clone drive")}><b>⇄</b><span>Clone drive<small>Verified device-to-device copy</small></span></button></div></section>
      <footer><span>Legacy Doctor · Local-first media preservation</span><span><i/>Verified local snapshot · destructive actions disabled</span></footer>
    </section>
  </main>;
}
