import React from 'react'
import { string, number, func, oneOfType, shape } from 'prop-types'
import { Form } from 'semantic-ui-react'
import { map } from 'ramda'

import * as enums from 'helpers/dataSourceEnums'
import statUnitTypes from 'helpers/statUnitTypes'

const numOrZero = value => Number(value) || 0

const unmap = map(([value, text]) => ({ value, text }))
const statUnitTypeOptions = unmap([[0, 'Any'], ...statUnitTypes]).filter(x => x.value < 4)
const priorities = unmap([[0, 'Any'], ...enums.priorities])
const operations = unmap([[0, 'Any'], ...enums.operations])

const getLocalizedOptions = (localize) => {
  const localizeArray = map(x => ({ ...x, text: localize(x.text) }))
  return {
    statUnitType: localizeArray(statUnitTypeOptions),
    allowedOperations: localizeArray(operations),
    priorities: localizeArray(priorities),
  }
}

const SearchForm = ({
  formData, onChange, onSubmit, localize,
}) => {
  const { wildcard = '', statUnitType = 0, priority = 0, allowedOperations = 0 } = formData
  const handleChange = (_, { name: propName, value }) => { onChange({ [propName]: value }) }
  const handleSubmit = (e) => {
    e.preventDefault()
    onSubmit(formData)
  }
  const options = getLocalizedOptions(localize)
  return (
    <Form onSubmit={handleSubmit}>
      <Form.Group widths="equal">
        <Form.Input
          type="text"
          name="wildcard"
          value={wildcard}
          onChange={handleChange}
          label={localize('SearchWildcard')}
          title={localize('SearchWildcard')}
        />
        <Form.Group>
          <Form.Select
            type="text"
            name="statUnitType"
            value={numOrZero(statUnitType)}
            onChange={handleChange}
            options={options.statUnitType}
            label={localize('StatUnit')}
            title={localize('StatUnit')}
          />
          <Form.Select
            type="text"
            name="priority"
            value={numOrZero(priority)}
            onChange={handleChange}
            options={options.priorities}
            label={localize('Priority')}
            title={localize('Priority')}
          />
          <Form.Select
            type="text"
            name="allowedOperations"
            value={numOrZero(allowedOperations)}
            onChange={handleChange}
            options={options.allowedOperations}
            label={localize('AllowedOperations')}
            title={localize('AllowedOperations')}
          />
        </Form.Group>
      </Form.Group>
      <Form.Button
        type="submit"
        content={localize('Search')}
        floated="right"
        style={{ marginBottom: 15 }}
        icon="search"
        primary
      />
    </Form>
  )
}

SearchForm.propTypes = {
  formData: shape({
    wildcard: string,
    statUnitType: oneOfType([number, string]),
    priority: oneOfType([number, string]),
    allowedOperations: oneOfType([number, string]),
  }).isRequired,
  onSubmit: func.isRequired,
  onChange: func.isRequired,
  localize: func.isRequired,
}

export default SearchForm
