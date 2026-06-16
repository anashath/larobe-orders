const C="lr-v37";
const STATIC=["/larobe-orders/","/larobe-orders/index.html","/larobe-orders/manifest.json"];

self.addEventListener("install",e=>{
  e.waitUntil(caches.open(C).then(c=>c.addAll(STATIC)).catch(()=>{}));
  self.skipWaiting();
});

self.addEventListener("activate",e=>{
  e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))));
  self.clients.claim();
});

self.addEventListener("fetch",e=>{
  // Always network-first for HTML so auth state is never stale
  if(e.request.mode==="navigate"||e.request.url.endsWith("index.html")||e.request.url.endsWith("/larobe-orders/")){
    e.respondWith(
      fetch(e.request).then(r=>{
        var rc=r.clone();
        caches.open(C).then(c=>c.put(e.request,rc));
        return r;
      }).catch(()=>caches.match(e.request))
    );
    return;
  }
  // Cache-first for other assets
  e.respondWith(
    caches.match(e.request).then(r=>r||fetch(e.request)).catch(()=>new Response("Offline"))
  );
});