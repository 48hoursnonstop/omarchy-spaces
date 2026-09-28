const assert = require('assert')
const matcher = require('../../qml/AppMatcher.js')

function entry(values) {
  return Object.assign({
    id: '',
    name: '',
    startupClass: '',
    startupWmClass: '',
    command: [],
    execString: ''
  }, values)
}

const foot = entry({
  id: 'org.codeberg.dnkl.foot',
  name: 'Foot',
  startupClass: 'foot',
  command: ['foot']
})
const firefox = entry({
  id: 'firefox',
  name: 'Firefox',
  startupClass: 'firefox',
  command: ['firefox']
})
const chromium = entry({
  id: 'chromium',
  name: 'Chromium',
  startupClass: 'chromium',
  command: ['chromium'],
  execString: 'chromium %U'
})
const steamGame = entry({
  id: 'steam-game-570',
  name: 'Dota 2',
  execString: 'steam steam://rungameid/570'
})
const webapp = entry({
  id: 'webapp-whatsapp',
  name: 'WhatsApp',
  execString: 'chromium --app=https://web.whatsapp.com/'
})
const rows = [foot, firefox, chromium, steamGame, webapp].map(e => ({ entry: e }))

assert.strictEqual(
  matcher.bestMatch({ className: 'foot', initialClass: 'foot', appId: 'foot', title: 'shell' }, rows).entry.id,
  foot.id
)

assert.strictEqual(
  matcher.bestMatch({ className: 'steam_app_570', initialClass: '', appId: '', title: 'Dota 2' }, rows).entry.id,
  steamGame.id
)

assert.strictEqual(
  matcher.bestMatch({ className: 'chromium', initialClass: 'chromium', appId: '', title: 'WhatsApp — Chromium' }, rows).entry.id,
  webapp.id
)

assert.strictEqual(
  matcher.bestMatch(
    { className: 'odd-app', initialClass: '', appId: '', title: 'Unknown' },
    rows,
    { 'odd-app': 'firefox' }
  ).entry.id,
  firefox.id
)

assert.strictEqual(
  matcher.bestMatch({ className: 'totally-unknown', initialClass: '', appId: '', title: 'Unknown' }, rows),
  null
)

console.log('app matcher ok')
