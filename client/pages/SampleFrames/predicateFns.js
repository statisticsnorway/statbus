import R from 'ramda'

import getUid from 'helpers/getUid'
import { createClauseDefaults } from './model'

const preconcat = R.flip(R.concat)
const dropLatest = R.dropLast(1)
const appendPath = path => (...next) => path.concat(next)

const ensure = (predicate) => {
  if (predicate == null) return predicate
  const left = ensure(predicate.left)
  const right = ensure(predicate.right)
  return predicate.clauses.length > 0 || left != null || right != null
    ? { ...predicate, left, right }
    : null
}

export const createTransformer = (...setters) => {
  const update = R.pipe(...setters)
  const transformer = predicate =>
    predicate == null
      ? predicate
      : {
        ...update(predicate),
        left: transformer(predicate.left),
        right: transformer(predicate.right),
      }
  return transformer
}

export const flatten = (predicate, path = [], shift = 0) => {
  if (predicate == null) return { clauses: [], maxShift: 0 }
  const pathTo = appendPath(path)
  const withMeta = (clause, i) => ({
    clause,
    path: pathTo('clauses', i),
    meta: { shift, startAt: [], endAt: [], allSelectedAt: [] },
  })
  const left = flatten(predicate.left, pathTo('left'), shift + 1)
  const right = flatten(predicate.right, pathTo('right'), shift + 1)
  const clauses = predicate.clauses.map(withMeta).concat(left.clauses, right.clauses)
  if (clauses.length > 0) {
    clauses[0].meta.startAt.unshift(shift)
    if (clauses.every(x => x.clause.selected)) clauses[0].meta.allSelectedAt.unshift(shift)
    R.last(clauses).meta.endAt.unshift(shift)
  }
  return {
    clauses,
    maxShift: Math.max(0, clauses.length > 0 ? shift : shift - 1, left.maxShift, right.maxShift),
  }
}

export const getSelected = (clauses) => {
  const isSequenceBreaking = path =>
    R.pipe(R.last, R.prop('path'), dropLatest, R.equals(dropLatest(path)))
  const isSequentTo = index =>
    R.anyPass([R.isEmpty, R.pipe(R.last, R.prop('index'), R.inc, R.equals(index))])
  const toSelectedSequential = (sequence, { clause, path, meta }, index) =>
    sequence === null
      ? null
      : clause.selected
        ? isSequentTo(index)(sequence) ? [...sequence, { clause, path, meta, index }] : null
        : sequence.length > 0 && isSequenceBreaking(path)(sequence) ? null : sequence
  return clauses.reduce(toSelectedSequential, [])
}

export const add = (path, at) => R.over(R.lensPath(path), R.insert(at, createClauseDefaults()))

export const edit = (path, data) => R.set(R.lensPath([...path, data.name]), data.value)

export const remove = path =>
  R.pipe(R.over(R.lensPath(dropLatest(path)), R.remove(R.last(path), 1)), ensure)

export const toggle = path => R.over(R.lensPath([...path, 'selected']), R.not)

export const toggleGroup = (predicate, path, selected) => {
  const lensesToToggle = ({ clauses, left, right }, subPath) => {
    const pathTo = appendPath(subPath)
    const toPathLensIfSelected = (acc, cur, i) =>
      cur.selected === selected ? acc : [...acc, R.lensPath(pathTo('clauses', i, 'selected'))]
    return clauses
      .reduce(toPathLensIfSelected, [])
      .concat(
        left != null ? lensesToToggle(left, pathTo('left')) : [],
        right != null ? lensesToToggle(right, pathTo('right')) : [],
      )
  }
  const pathsToToggle = lensesToToggle(R.view(R.lensPath(path), predicate), path)
  const toggleLenses = pathsToToggle.map(lens => R.set(lens, selected))
  const update = R.pipe(...toggleLenses)
  return update(predicate)
}

export const toggleAll = (selected) => {
  const selectedLens = R.lensProp('selected')
  const toToggled = R.cond([
    [R.pipe(R.view(selectedLens), R.equals(selected)), R.identity],
    [R.T, R.set(selectedLens, selected)],
  ])
  return createTransformer(R.over(R.lensProp('clauses'), R.map(toToggled)))
}

export const group = (predicate, selected) => [predicate, selected]

export const ungroup = (predicate, path) => {
  const lensesToElevate = ({ clauses, left, right }, subPath) => {
    const pathTo = appendPath(subPath)
    return (clauses.length > 0 ? [R.lensPath(pathTo('clauses'))] : []).concat(
      left != null ? lensesToElevate(left, pathTo('left')) : [],
      right != null ? lensesToElevate(right, pathTo('right')) : [],
    )
  }
  const targetLens = R.lensPath(R.update(path.length - 1, 'clauses', path))
  const elevateClause = R.pipe(lens => R.view(lens, predicate), preconcat, R.over(targetLens))
  const sourceLenses = lensesToElevate(R.view(R.lensPath(path), predicate), path)
  const removePredicate = R.set(R.lensPath(path), undefined)
  const update = R.pipe(...sourceLenses.map(elevateClause), removePredicate, ensure)
  return update(predicate)
}

export const fromExpressionEntry = R.over(
  R.lensProp('clauses'),
  R.map(({ expressionEntry, comparison }) => ({
    ...expressionEntry,
    comparison: comparison === null ? -1 : comparison,
  })),
)

export const toExpressionEntry = R.over(
  R.lensProp('clauses'),
  R.map(({ field, operation, value, comparison }) => ({
    expressionEntry: { field, operation, value },
    comparison: comparison === -1 ? null : comparison,
  })),
)

export const setUids = R.over(
  R.lensProp('clauses'),
  R.map(clause => ({ ...clause, uid: getUid() })),
)
