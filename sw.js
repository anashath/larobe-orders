const C="lr-v51",A=["/larobe-orders/","/larobe-orders/index.html"];self.addEventListener("install",e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(A)).catch(()=>{}));self.skipWaiting();});self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.map(x=>caches.delete(x)))));self.clients.claim();});self.addEventListener("fetch",e=>{if(e.request.mode==="navigate"){e.respondWith(fetch(e.request,{cache:"no-store"}).then(r=>{var rc=r.clone();caches.open(C).then(c=>c.put(e.request,rc));return r;}).catch(()=>caches.match(e.request)));return;}e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)).catch(()=>new Response("Offline")));});

self.addEventListener("push",e=>{
  var data={};
  try{data=e.data?e.data.json():{};}catch(err){data={title:"La Robe Orders",body:e.data?e.data.text():""};}
  var title=data.title||"La Robe Orders";
  var opts={
    body:data.body||"",
    icon:"icons/icon-192.png",
    badge:"icons/icon-192.png",
    data:{url:data.url||"/larobe-orders/index.html"},
    vibrate:[100,50,100]
  };
  e.waitUntil(self.registration.showNotification(title,opts));
});

self.addEventListener("notificationclick",e=>{
  e.notification.close();
  var url=(e.notification.data&&e.notification.data.url)||"/larobe-orders/index.html";
  e.waitUntil(
    self.clients.matchAll({type:"window",includeUncontrolled:true}).then(function(list){
      for(var i=0;i<list.length;i++){
        var c=list[i];
        if(c.url.indexOf("/larobe-orders/")>=0 && "focus" in c) return c.focus();
      }
      if(self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
