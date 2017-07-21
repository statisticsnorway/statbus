import { parse as parseXml } from 'fast-xml-parser'
import { parse as parseCsv } from 'papaparse'
import { pipe, union, keys, values } from 'ramda'

const isObject = data => data && typeof (data) === 'object'
const hasNested = data => values(data).some(isObject)
const unionBy = asFn => (prev, curr) => union(prev, asFn(curr))

const getAttributes = data => Array.isArray(data)
  ? data.reduce(unionBy(keys), [])
  : isObject(data)
    ? hasNested(data)
      ? values(data).reduce(unionBy(getAttributes), [])
      : keys(data)
    : []

const polishParsedCsv = result => result.data

export const parseXML = pipe(parseXml, getAttributes)
export const parseCSV = pipe(parseCsv, polishParsedCsv, getAttributes)
