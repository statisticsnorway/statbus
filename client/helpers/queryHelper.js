import { pipe } from 'ramda'

const shouldBeMapped = ([, value]) => typeof (value) === 'number' || value

const prefix = index => str =>
  index === 0
    ? `?${str}`
    : str

const encode = ([key, value]) => str =>
  `${str}${encodeURIComponent(key)}=${encodeURIComponent(value)}`

const append = length => index => str =>
  index !== length - 1
    ? `${str}&`
    : str

export default (queryParams) => {
  const pairs = Object.entries(queryParams).filter(shouldBeMapped)
  const postfix = append(pairs.length)
  const reducer = (str, pair, i) => pipe(encode(pair), postfix(i), prefix(i))(str)
  return pairs.reduce(reducer, '')
}
