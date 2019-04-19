import { parse as parseXml } from 'fast-xml-parser'
import { parse as parseCsv } from 'papaparse'
import { pipe, union, keys, values } from 'ramda'

function isObject(data) {
  return data != null && typeof data === 'object'
}
function hasNested(data) {
  return values(data).some(isObject)
}
function unionBy(asFn) {
  return function comapare(prev, curr) {
    return union(prev, asFn(curr))
  }
}

const keyify = (obj, prefix = '') =>
  Object.keys(obj).reduce((res, el) => {
    if (Array.isArray(obj[el]) && obj[el].length > 0) {
      return [...res, ...keyify(obj[el][0], `${prefix + el}.`)]
    } else if (typeof obj[el] === 'object' && obj[el] !== null) {
      return [...res, ...keyify(obj[el], `${prefix + el}.`)]
    }
    return [...res, prefix + el]
  }, [])

function getXmlAttributes(parsed) {
  return Array.isArray(parsed) && parsed.length > 0
    ? keyify(parsed[0])
    : isObject(parsed)
      ? hasNested(parsed)
        ? values(parsed).reduce(unionBy(getXmlAttributes), [])
        : keys(parsed)
      : []
}

function getCsvAttributes(parsed) {
  const startFrom = parsed.data.findIndex(x => x.length > 1)
  return {
    attributes: parsed.data[startFrom],
    delimiter: parsed.meta.delimiter,
    startFrom,
  }
}

export const fromXml = pipe(
  parseXml,
  getXmlAttributes,
)
export const fromCsv = pipe(
  parseCsv,
  getCsvAttributes,
)
