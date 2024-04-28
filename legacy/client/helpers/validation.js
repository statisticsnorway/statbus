/* eslint-disable consistent-return,arrow-parens,no-shadow */
import { shape } from 'prop-types'
import { pipe, anyPass, isNil, isEmpty, any, values, not } from 'ramda'

import { isDateInThePast } from './dateHelper.js'
import { endsWithAny } from './string.js'

const simpleRoutes = [
  { key: 'StatUnitSearch', route: '/' },
  { key: 'StatUnitUndelete', route: '/statunits/deleted' },
  { key: 'StatUnitCreate', route: '/statunits/create/2' },
  { key: 'SampleFramesView', route: '/sampleframes' },
  { key: 'SampleFramesCreate', route: '/sampleframes/create' },
  { key: 'DataSources', route: '/datasources' },
  { key: 'DataSourcesCreate', route: '/datasources/create' },
  { key: 'DataSourcesUpload', route: '/datasources/upload' },
  { key: 'DataSourceQueues', route: '/datasourcesqueue' },
  { key: 'Users', route: '/users' },
  { key: 'UserCreate', route: '/users/create' },
  { key: 'Roles', route: '/roles' },
  { key: 'RoleCreate', route: '/roles/create' },
  { key: 'Analysis', route: '/analysisqueue' },
  { key: 'EnqueueNewItem', route: '/analysisqueue/create' },
  { key: 'Reports', route: '/reportsTree' },
  { key: 'AccountView', route: '/account' },
  { key: 'AccountEdit', route: '/account/edit' },
  { key: 'About', route: '/about' },
]

export const findMatchAndLocalize = (nextRoute, localize) => {
  const symbols = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']
  let localizedValue = localize('NotFoundMessage')

  if (nextRoute.includes('statunits/view') && endsWithAny(symbols, nextRoute)) {
    localizedValue = localize('StatUnitView')
  }
  if (nextRoute.includes('statunits/edit') && endsWithAny(symbols, nextRoute)) {
    localizedValue = localize('StatUnitEdit')
  }
  if (
    nextRoute.includes('statunits/links') &&
    (!nextRoute.includes('statunits/links/create') || !nextRoute.includes('statunits/links/delete'))
  ) {
    localizedValue = localize('LinkView')
  }
  if (nextRoute.includes('statunits/links/delete')) {
    localizedValue = localize('LinkDelete')
  }
  if (nextRoute.includes('statunits/links/create')) {
    localizedValue = localize('LinkCreate')
  }
  if (nextRoute.includes('sampleframes') && endsWithAny(symbols, nextRoute)) {
    localizedValue = localize('SampleFramesEdit')
  }
  if (nextRoute.includes('sampleframes/preview')) {
    localizedValue = localize('SampleFramesPreview')
  }
  if (nextRoute.includes('datasources/edit')) {
    localizedValue = localize('DataSourceEdit')
  }
  if (nextRoute.includes('datasourcesqueue') && nextRoute.includes('log')) {
    if (nextRoute.endsWith('log')) {
      localizedValue = localize('DataSourceQueuesPreview')
    } else {
      localizedValue = localize('DataSourceQueuesRevise')
    }
  }
  if (nextRoute.includes('users/edit')) {
    localizedValue = localize('UserEdit')
  }
  if (nextRoute.includes('roles/edit')) {
    localizedValue = localize('RoleList_EditRole')
  }
  if (nextRoute.includes('analysisqueue')) {
    if (nextRoute.endsWith('log')) {
      localizedValue = localize('ViewAnalysisQueueLogs')
    } else {
      localizedValue = localize('ViewAnalysisQueueLogsRevise')
    }
  }

  simpleRoutes.forEach(el => {
    if (el.route === nextRoute) {
      localizedValue = localize(el.key)
    }
  })

  return localizedValue
}

export const getSearchFormErrors = (formData, localize) => {
  const errors = {}
  if (formData.turnoverFrom && formData.turnoverTo) {
    if (parseInt(formData.turnoverFrom, 10) > parseInt(formData.turnoverTo, 10)) {
      errors.turnoverError = `${localize('TurnoverTo')} ${localize('CantBeLessThan')} ${localize('TurnoverFrom')}`
    } else {
      delete errors.turnoverError
    }
  }
  if (formData.employeesNumberFrom && formData.employeesNumberTo) {
    if (parseInt(formData.employeesNumberFrom, 10) > parseInt(formData.employeesNumberTo, 10)) {
      errors.employeesNumberError = `${localize('NumberOfEmployeesTo')} ${localize('CantBeLessThan')} ${localize('NumberOfEmployeesFrom')}`
    } else {
      delete errors.employeesNumberError
    }
  }

  return errors
}

export const nullsToUndefined = obj =>
  Object.entries(obj).reduce(
    (rest, [key, value]) => ({ ...rest, [key]: value === null ? undefined : value }),
    {},
  )

export const hasValue = pipe(
  anyPass([isNil, isEmpty]),
  not,
)

export const confirmIsEmpty = formData => {
  const { sortRule, ...copyFormData } = formData
  return (
    Object.entries(copyFormData)
      .map(v => v[1])
      .filter(x => !isEmpty(x) && !isNil(x) && x !== false).length === 0
  )
}

export const confirmHasOnlySortRule = formData => {
  const filtering = key =>
    !isNil(formData[key]) && !isEmpty(formData[key]) && formData[key] !== false
  const keys = Object.keys(formData)
  const correctKeys = keys.filter(filtering)
  let hasOnlySortRule
  correctKeys.forEach(key => {
    hasOnlySortRule = key === 'sortRule' && formData.sortRule === 1
  })

  return hasOnlySortRule
}

export const getCorrectQuery = formData => {
  const keys = Object.keys(formData)
  return keys.reduce((acc, key) => {
    if (isEmpty(formData[key])) {
      return acc
    }
    acc[key] = formData[key]
    return acc
  }, {})
}

export const isAllowedValue = (str, separator) => {
  const allowedCharacters = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', ...separator]
  let isAllowed
  for (let i = 0; i < str.length; i++) {
    const character = str.charAt(i)
    isAllowed = allowedCharacters.includes(character)
  }
  return isAllowed
}

export const getSeparator = (field, operation) => {
  const operations = [1, 2, 3, 4, 5, 6, 9, 10]
  let separator = ''
  if (field === 5 && (operation === 1 || operation === 2)) {
    separator = ['.', '-']
  }
  if (field === 5 && (operation === 11 || operation === 12)) {
    separator = ['.', ',', '-']
  }
  if ((field === 6 || field === 7 || field === 8) && operations.includes(operation)) {
    separator = ['']
  }
  if ((field === 6 || field === 7 || field === 8) && (operation === 11 || operation === 12)) {
    separator = [',']
  }
  return separator
}

export const filterPredicateErrors = errors => {
  const getClausesErrors = errors => {
    if (errors.clauses) {
      return errors.clauses
    } else if (errors.predicates) {
      return getClausesErrors(errors.predicates[0])
    }
  }
  return getClausesErrors(errors)
    .filter(x => hasValue(x))
    .reduce((acc, el) => {
      if (!acc.includes(el.value)) {
        acc.push(el.value)
        return acc
      }
      return acc
    }, [])
}

export const hasValues = pipe(
  values,
  any(hasValue),
)

export const ensureArray = value => (Array.isArray(value) ? value : value ? [value] : [])

export const shapeOf = fields => propType =>
  shape(fields.reduce((acc, curr) => ({ ...acc, [curr]: propType }), {}))

// eslint-disable-next-line consistent-return
export const createPropType = mapPropsToPropTypes => (props, propName, componentName, ...rest) => {
  const propType = mapPropsToPropTypes(props, propName, componentName)
  const error = propType(props, propName, componentName, ...rest)
  if (error) return error // WIP - not sure what exactly, seems to be working fine...
}

export const hasValueAndInThePast = x => hasValue(x) && isDateInThePast(x)
