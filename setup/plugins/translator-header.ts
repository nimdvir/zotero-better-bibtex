import * as fs from 'fs'
import * as path from 'path'
import * as ejs from 'ejs'
import { ConcatSource } from 'webpack-sources'
import * as crypto from 'crypto'

import version from 'zotero-plugin/version'
import root from 'zotero-plugin/root'

import stringify = require('json-stable-stringify')

const preferences = require(path.join(root, 'gen/preferences/defaults.json'))
const translators = require(path.join(root, 'gen/translators.json'))

function hash(str) {
  return crypto.createHash('md5').update(str).digest('hex')
}

class TranslatorHeaderPlugin {
  private translator: string

  constructor(translator) {
    this.translator = translator
  }

  public apply(compiler) {
    compiler.hooks.emit.tap('TranslatorHeaderPlugin', compilation => {
      const asset = this.translator + '.js'

      const header = JSON.parse(JSON.stringify(translators.byName[this.translator]))
      const headerCode = ejs.render(
        fs.readFileSync(path.join(__dirname, 'translator-header.ejs'), 'utf8'),
        {preferences, header, version}
      )

      delete header.description
      header.configOptions = header.configOptions || {}
      // header.configOptions.hash = crypto.createHash('md5').update(headerCode + compilation.assets[asset].source()).digest('hex')
      // header.configOptions.hash = [crypto.createHash('md5').update(headerCode).digest('hex')].concat(compilation.chunks.map(chunk => chunk.hash)).join('-')
      header.configOptions.hash = [headerCode, compilation.assets[asset].source()].map(hash).join('-')

      // because Zotero doesn't allow headers that have a object at the last key, so put lastUpdated at the end as a safeguard
      const header_order = [
        'translatorID',
        'translatorType',
        'label',
        'creator',
        'target',
        'minVersion',
        'maxVersion',
        'priority',
        'inRepository',
        'configOptions',
        'displayOptions',
        'exportCharset',
        'exportNotes',
        'exportFileData',
        'useJournalAbbreviation',
      ]
      const json_header = stringify(header, {
        space: 2,
        cmp: (a, b) => {
          // lastUpdated always at the end
          if (a.key === 'lastUpdated') return 1
          if (b.key === 'lastUpdated') return -1

          a.pos = (header_order.indexOf(a.key) + 1) || header_order.length + 1
          b.pos = (header_order.indexOf(b.key) + 1) || header_order.length + 1
          if (a.pos !== b.pos) return a.pos - b.pos
          return a.key.localeCompare(b.key) // can only happen if they're both not in the order
        },
      }) + '\n\n'

      compilation.assets[asset] = new ConcatSource(json_header + headerCode, compilation.assets[asset])
    })
  }
}

export = TranslatorHeaderPlugin
