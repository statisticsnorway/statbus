import * as R from 'ramda'

import getUid from '/helpers/getUid'
import { createClauseDefaults } from './model.js'

const preconcat = R.flip(R.concat)
const dropLatest = R.dropLast(1)
const appendPath = path => (...next) => path.concat(next)
const notNil = R.pipe(R.isNil, R.not)

const ensure = (predicate, depth = 0) => {
  if (predicate === undefined) return undefined
  const clauses = predicate.clauses.filter(notNil)
  if (depth === 0 && clauses.length > 0) clauses[0].comparison = undefined
  const predicates =
    predicate.predicates != null
      ? predicate.predicates.map(p => ensure(p, depth + 1)).filter(notNil)
      : []
  return clauses.length > 0 || predicates.length > 0 ? { clauses, predicates } : undefined
}

export const flatten = (predicate, path = [], shift = 0) => {
  const pathTo = appendPath(path)
  const withMeta = (clause, i) => ({
    clause,
    path: pathTo('clauses', i),
    meta: { shift, startAt: [], endAt: [], allSelectedAt: [] },
  })
  const next = predicate.predicates.map((pred, i) =>
    flatten(pred, pathTo('predicates', i), shift + 1))
  const clauses = predicate.clauses.map(withMeta).concat(...next.map(x => x.clauses))
  if (clauses.length > 0) {
    clauses[0].meta.startAt.unshift(shift)
    if (clauses.every(x => x.clause.selected)) clauses[0].meta.allSelectedAt.unshift(shift)
    R.last(clauses).meta.endAt.unshift(shift)
  }
  return {
    clauses,
    maxShift: Math.max(0, clauses.length > 0 ? shift : shift - 1, ...next.map(x => x.maxShift)),
  }
}

export const getSequentiallySelected = (flattenedClauses) => {
  const isSequenceBreaking = path =>
    R.pipe(R.last, R.prop('path'), dropLatest, R.equals(dropLatest(path)))
  const isSequentTo = index =>
    R.anyPass([R.isEmpty, R.pipe(R.last, R.prop('index'), R.inc, R.equals(index))])
  const toSelectedSequential = (sequence, { clause, path, meta }, index) =>
    sequence === undefined
      ? sequence
      : clause.selected
        ? isSequentTo(index)(sequence)
          ? R.append({ clause, path, meta, index })(sequence)
          : undefined
        : sequence.length > 0 && isSequenceBreaking(path)(sequence)
          ? undefined
          : sequence
  return flattenedClauses.reduce(toSelectedSequential, []) || []
}

export const add = (path, at) => R.over(R.lensPath(path), R.insert(at, createClauseDefaults()))

export const addHeadClause = (predicate, firstClausePath) => {
  const { comparison, ...clause } = createClauseDefaults()
  const setComparison = R.set(R.lensPath(R.append('comparison', firstClausePath)), comparison)
  const updateCurrentHead = firstClausePath !== undefined ? setComparison : R.identity
  const setNewHead = R.over(R.lensProp('clauses'), R.prepend(clause))
  const update = R.pipe(updateCurrentHead, setNewHead)
  return update(predicate)
}

export const edit = (path, data) => {
  if (data.name === 'field') {
    return R.pipe(
      R.set(R.lensPath(R.append(data.name)(path)), data.value),
      R.set(R.lensPath(R.append('operation')(path)), 1),
      R.set(R.lensPath(R.append('value')(path)), ''),
    )
  }
  if (data.name === 'operation') {
    return R.pipe(
      R.set(R.lensPath(R.append(data.name)(path)), data.value),
      R.set(R.lensPath(R.append('value')(path)), ''),
    )
  }
  return R.set(R.lensPath(R.append(data.name)(path)), data.value)
}

export const remove = path =>
  R.pipe(R.over(R.lensPath(dropLatest(path)), R.remove(R.last(path), 1)), ensure)

export const toggle = path => R.over(R.lensPath(R.append('selected')(path)), R.not)

export const toggleGroup = (predicate, path, selected) => {
  const lensesToToggle = ({ clauses, predicates }, subPath) => {
    const pathTo = appendPath(subPath)
    const toPathLensIfSelected = (lenses, clause, i) =>
      clause.selected === selected
        ? lenses
        : R.append(R.lensPath(pathTo('clauses', i, 'selected')))(lenses)
    return clauses
      .reduce(toPathLensIfSelected, [])
      .concat(...predicates.map((pred, i) => lensesToToggle(pred, pathTo('predicates', i))))
  }
  const groupPath = R.dropLast(2, path)
  const pathsToToggle = lensesToToggle(R.view(R.lensPath(groupPath), predicate), groupPath)
  const toggleLenses = pathsToToggle.map(lens => R.set(lens, selected))
  const update = R.pipe(...toggleLenses)
  return update(predicate)
}

const createTransformer = (...setters) => {
  const update = R.pipe(...setters)
  const transformer = ({ predicates, ...rest }) => ({
    ...update(rest),
    predicates: predicates.map(transformer),
  })
  return transformer
}

export const toggleAll = (selected) => {
  const ensureSelected = R.cond([
    [R.pipe(R.view(R.lensProp('selected')), R.equals(selected)), R.identity],
    [R.T, R.set(R.lensProp('selected'), selected)],
  ])
  return createTransformer(R.over(R.lensProp('clauses'), R.map(ensureSelected)))
}

const findSeed = (...arrays) => {
  if (arrays.length === 0) return []
  if (arrays.length === 1) return arrays[0]
  const shortest = arrays.reduce((acc, cur) => (cur.length < acc.length ? cur : acc), arrays[0])
  for (let i = 0; i < shortest.length; i++) {
    if (!arrays.every(R.startsWith(R.take(i + 1, shortest)))) {
      return R.take(i, shortest)
    }
  }
  return [...shortest]
}

export const group = (predicate, selectedPaths) => {
  const commonPath = findSeed(...selectedPaths)
  const toTargetPath = R.pipe(
    ...(R.endsWith(['clauses'], commonPath)
      ? [R.insertAll(commonPath.length - 1, ['predicates', 0])]
      : R.endsWith(['predicates'], commonPath)
        ? [
          R.drop(commonPath.length - 1),
          R.concat(R.append(selectedPaths[0][commonPath.length], commonPath)),
        ]
        : [R.drop(commonPath.length), R.concat(R.concat(commonPath, ['predicates', 0]))]),
    R.dropLast(1),
  )
  const toElevateSetter = path =>
    R.over(R.lensPath(toTargetPath(path)), R.append(R.view(R.lensPath(path), predicate)))
  const toEraseSetter = path => R.set(R.lensPath(path), undefined)
  const update = R.pipe(
    ...selectedPaths.map(toElevateSetter),
    ...selectedPaths.map(toEraseSetter),
    ensure,
    toggleAll(false),
  )

  return update(predicate)
}

const pathsToElevate = ({ clauses, predicates }, subPath) => {
  const pathTo = appendPath(subPath)
  const subPaths = predicates.map((pred, i) => pathsToElevate(pred, pathTo('predicates', i)))
  return (clauses.length > 0 ? [pathTo('clauses')] : []).concat(...subPaths)
}

export const ungroup = (predicate, path) => {
  const groupPath = R.dropLast(2, path)
  const sourcePaths = pathsToElevate(R.view(R.lensPath(groupPath), predicate), groupPath)
  const targetLens = R.lensPath(R.append('clauses', R.dropLast(2, groupPath)))
  const toElevateSetter = R.pipe(
    R.lensPath,
    lens => R.view(lens, predicate),
    preconcat,
    R.over(targetLens),
  )
  const eraseSetter = R.set(R.lensPath(groupPath), undefined)
  const update = R.pipe(...sourcePaths.map(toElevateSetter), eraseSetter, ensure)
  return update(predicate)
}

export const fromVm = ({ predicate, comparison }) => ({
  predicates: predicate.groups.map(fromVm),
  clauses: predicate.rules.map((rule, i) => ({
    ...rule.predicate,
    comparison: i === 0 ? comparison : rule.comparison,
    uid: getUid(),
  })),
})

export const toVm = ({ clauses, predicates }) => ({
  predicate: {
    groups: predicates.map(toVm),
    rules: clauses.map(({ comparison, field, operation, value }) => ({
      comparison,
      predicate: { field, operation, value },
    })),
  },
  comparison: clauses[0] && clauses[0].comparison,
})
