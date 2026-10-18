#!/usr/bin/env python3
"""Real host, loopback sockets and a private named pasteboard; never reads the user's clipboard."""
import base64, json, os, pathlib, re, socket, struct, subprocess, sys, time, uuid
root = pathlib.Path(__file__).resolve().parents[2]
out = root / '.build' / 'clipboard-images-integration'
out.mkdir(parents=True, exist_ok=True)
board = 'me.saffer.sill.test.images.' + uuid.uuid4().hex
helper = str(out / 'board')
def paste(*args):
    return subprocess.check_output([helper, *args], text=True).strip()
paste('make', str(out / 'sample.png'))
image = (out / 'sample.png').read_bytes()
env = dict(os.environ, SILL_TEST_LOOPBACK='1', SILL_TEST_PASTEBOARD=board, SILL_TEST_CLIPBOARD_LOG='1')
log = open(out / 'host.log', 'w')
host = subprocess.Popen([str(root / '.build/release/SillHost'), '--synthetic'], env=env, stdout=log, stderr=subprocess.STDOUT)
clients = []
def send(s, value, kind=32):
    payload = json.dumps(value).encode() if isinstance(value, dict) else value
    s.sendall(struct.pack('>BdBI', kind, time.time(), 0, len(payload)) + payload)
def receive(s, duration=.8):
    result, deadline = [], time.monotonic()+duration
    def exact(n):
        data=b''
        while len(data)<n:
            chunk=s.recv(n-len(data))
            if not chunk: raise RuntimeError('host disconnected')
            data+=chunk
        return data
    while time.monotonic()<deadline:
        s.settimeout(max(.01, deadline-time.monotonic()))
        try: header=exact(14)
        except socket.timeout: break
        kind, _, _, size=struct.unpack('>BdBI', header)
        s.settimeout(5)
        body=exact(size)
        if kind==32: result.append(json.loads(body))
    return result
try:
    for _ in range(150):
        text=(out/'host.log').read_text()
        listeners=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(host.pid),'-iTCP','-sTCP:LISTEN','-Fn'],capture_output=True,text=True).stdout
        match=re.search(r'n127\.0\.0\.1:(\d+)', listeners)
        if match: break
        if host.poll() is not None: raise RuntimeError(text)
        time.sleep(.3)
    else: raise RuntimeError('No host port in '+text)
    port=int(match[1])
    for _ in range(3):
        s=socket.create_connection(('127.0.0.1',port),timeout=5); clients.append(s)
    legacy, updated, sender=clients
    send(legacy,{})
    send(updated,{'accepts':2})
    send(sender,{'accepts':2})
    for s in clients: receive(s,.25)
    # A device image becomes a native Mac pasteboard image and reaches only capable peers.
    send(sender,{'image':base64.b64encode(image).decode(),'accepts':2})
    assert receive(updated)[0]['image']==base64.b64encode(image).decode(), 'device image forwarding'
    assert receive(legacy)==[], 'legacy subscriber received image'
    assert receive(sender)==[], 'image echoed to sender'
    assert paste('get',board)==base64.b64encode(image).decode(), 'Mac pasteboard image write'
    print('PASS: device image -> Mac + capable peer, legacy filtering and no echo')
    paste('image',board,str(out/'sample.png'))
    for s in (updated,sender):
        clips=receive(s)
        assert len(clips)==1 and len(base64.b64decode(clips[0]['image']))>0, 'Mac image not delivered'
    assert receive(legacy)==[], 'Mac image reached legacy peer'
    print('PASS: Mac image -> capable subscribers only')
    paste('image',board,str(out/'sample.png'),'org.nspasteboard.ConcealedType')
    for s in clients: assert receive(s)==[], 'concealed image leaked'
    print('PASS: concealed Mac image stays private')
    paste('text',board,'image-test-text')
    for s in clients: assert receive(s)==[{'text':'image-test-text'}], 'text compatibility'
    print('PASS: text reaches both generations')
    for s in clients: send(s,{'stop':True})
    time.sleep(.3)
    paste('image',board,str(out/'sample.png'))
    for s in clients: assert receive(s)==[], 'stopped peer received image'
    print('PASS: stop ends image delivery')
finally:
    for s in clients: s.close()
    host.terminate()
    try: host.wait(timeout=5)
    except subprocess.TimeoutExpired: host.kill(); host.wait()
    log.close()
    paste('release',board)
