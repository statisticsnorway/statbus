import { max, min, pipe, range, sort, uniq } from 'ramda'

export const getPagesRange = (ambiguousCurrent = 1, ambiguousTotal = 1) => {
  const current = ambiguousCurrent || 1
  const total = ambiguousTotal || 1
  const leftside = current < 5
  const rightside = current > total - 4
  const middleRange = () => range(max(current - 1, 3), min(current + 2, total + 1))
  return total < 9
    ? range(1, (total || 1) + 1)
    : [
      ...range(1, leftside ? current + 2 : 2),
      ...(leftside ? [] : ['. ..']),
      ...(leftside || rightside ? [] : middleRange()),
      ...(rightside ? [] : ['.. .']),
      ...range((rightside ? current : total) - 1, total + 1),
    ]
}

export const defaultPageSize = 10

const byAsc = (a, b) => a - b
export const getPageSizesRange = (current = defaultPageSize, options = [5, 10, 15, 25, 50]) =>
  pipe(uniq, sort(byAsc))(options.concat(Number.isNaN(current) ? [] : [current]))
