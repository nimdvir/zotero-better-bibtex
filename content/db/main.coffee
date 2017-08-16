Loki = require('./loki.coffee')
debug = require('../debug.coffee')
Prefs = require('../preferences.coffee')

if Prefs.get('testing')
  stringify = (data) -> JSON.stringify(data, null, 2)
else
  stringify = (data) -> JSON.stringify(data)

class DBStore
  mode: 'reference'

  conn: {}
  validName: /^better-bibtex[-_a-zA-Z0-9]*$/

  exportDatabase: (dbname, dbref, callback) ->
    debug('DBStore.exportDatabase:', dbname)

    conn = @conn[dbname]
    if conn == false
      debug('DBStore: save of', dbname, 'attempted after close')
      return callback(null)

    throw new Error("Database #{dbname} not loaded") unless conn

    do Zotero.Promise.coroutine(->
      try
        yield conn.executeTransaction(->
          for coll in dbref.collections
            if coll.dirty
              name = "#{dbname}.#{coll.name}"
              debug('DBStore.exportDatabase:', name)
              conn.queryAsync("REPLACE INTO \"#{dbname}\" (name, data) VALUES (?, ?)", [name, stringify(coll)])

          # TODO: only save if dirty? What about collection removal? Other data that may have changed on the DB?
          conn.queryAsync("REPLACE INTO \"#{dbname}\" (name, data) VALUES (?, ?)", [dbname, stringify(Object.assign({}, dbref, {collections: dbref.collections.map((coll) -> coll.name)}))])

          return
        )
        return callback(null)
      catch err
        return callback(err)
    )

    return

  # this assumes Zotero.initializationPromise has resolved, will throw an error if not
  loadDatabase: (dbname, callback) ->
    debug('DBStore.loadDatabase:', dbname)
    throw new Error("Invalid database name '#{dbname}'") unless dbname.match(@validName)
    throw new Error("Database '#{dbname}' already closed") if @conn[dbname] == false
    throw new Error("Database '#{dbname}' already loaded") if @conn[dbname]

    conn = @conn[dbname] = new Zotero.DBConnection(dbname)

    do Zotero.Promise.coroutine(->
      try
        yield conn.executeTransaction(->
          yield conn.queryAsync("CREATE TABLE IF NOT EXISTS \"#{dbname}\" (name TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL)")

          db = null
          collections = {}
          for row in yield conn.queryAsync("SELECT name, data FROM \"#{dbname}\"")
            if row.name == dbname
              db = JSON.parse(row.data)
            else
              try
                collections[row.name] = JSON.parse(row.data)
              catch err
                debug("DBStore.loadDatabase: failed to parse #{dbname}.#{row.name}")

          db.collections = (collections[coll] for coll in db.collections when collections[coll]) if db

          return callback(db)
        )
      catch err
        return callback(err)
    )
    return

  close: (dbname, callback) ->
    debug('DBStore.close', dbname)

    return callback(null) unless @conn[dbname]

    conn = @conn[dbname]
    @conn[dbname] = false

    do Zotero.Promise.coroutine(->
      try
        yield conn.closeDatabase(true)
        debug('DBStore.close OK', dbname)
        return callback(null)
      catch err
        debug('DBStore.close FAILED', dbname, err)
        return callback(err)
    )
    return

DB = new Loki('better-bibtex', {
  autosave: true,
  autosaveInterval: 5000,
  autosaveOnIdle: true,
  adapter: new DBStore(),
  autoexport: {
    proto: Object,
    inflate: (src, dest) ->
      Object.assign(dest, src)

      for date in ['scheduled', 'updated']
        if dest[date]
          dest[date] = Date.parse(dest[date])
          dest[date] = null is isNaN(dest[date])
        delete dest[date] unless dest[date]
      return
  }
})

DB.init = Zotero.Promise.coroutine(->
  yield DB.loadDatabaseAsync()

  DB.schemaCollection('citekey', {
    indices: [ 'itemID', 'libraryID', 'citekey', 'pinned' ],
    schema: {
      type: 'object'
      properties: {
        itemID: { type: 'integer' }
        libraryID: { type: 'integer' }
        citekey: { type: 'string' }
        pinned: { coerce: 'boolean', default: false }
        extra: { coerce: 'string', default: '' }
      }
      required: [ 'itemID', 'libraryID', 'citekey', 'extra' ]
    }
  })

  ###
  DB.schemaCollection('autoexport', {
    indices: [ 'type', 'id', 'status', 'path', 'exportNotes', 'translatorID', 'useJournalAbbreviation'],
    unique: [ 'path' ],
    schema: {
      type: 'object'
      properties: {
        status: { enum: ['running', 'done', 'error' ] }
        scheduled: { coerce: 'date' }
        updated: { coerce: 'date' }
        type: { enum: ['search', 'collection', 'library' ] }
        id: { type: 'integer' }
        exportNotes: { coerce: 'boolean' }
        useJournalAbbreviation: { coerce: 'boolean' }
        translatorID: { type: 'string' }
        path: { type: 'string' }
      }
      required: [ 'type', 'id', 'status', 'path', 'translatorID'],
    }
  })
  ###

  return
)

### old junk, only for json-backed storage
DB.removeCollection('metadata') if DB.getCollection('metadata')
DB.removeCollection('keys') if DB.getCollection('keys')
###

### only for json-backed storage
for ae in autoexports.data()
  # upgrade old autoexports
  if ae.collection
    [ ae.type, ae.id ] = ae.collection.split(':')
    ae.id ?= Zotero.Libraries.userLibraryID
    delete ae.collection
    autoexports.update(ae)

  # interrupted at start
  if ae.status == 'running'
    ae.scheduled = new Date()
    ae.status = 'done'
  else
    delete ae.scheduled
  autoexports.update(ae)
###

module.exports = DB