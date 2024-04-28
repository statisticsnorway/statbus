import React from 'react'
import { string, number, func, oneOfType, shape } from 'prop-types'
import { Form, Grid } from 'semantic-ui-react'
import { map } from 'ramda'

import * as enums from '/helpers/enums'

const numOrZero = value => Number(value) || 0

const unmap = map(([value, text]) => ({ value, text }))
const statUnitTypeOptions = unmap([[0, 'Any'], ...enums.statUnitTypes]).filter(x => x.value < 4)
const priorities = unmap([[0, 'Any'], ...enums.dataSourcePriorities])
const operations = unmap([[0, 'Any'], ...enums.dataSourceOperations])

const getLocalizedOptions = (localize) => {
  const localizeArray = map(x => ({ ...x, text: localize(x.text) }))
  return {
    statUnitType: localizeArray(statUnitTypeOptions),
    allowedOperations: localizeArray(operations),
    priorities: localizeArray(priorities),
  }
}

const SearchForm = ({ formData, onChange, onSubmit, localize }) => {
  const { wildcard = '', statUnitType = 0, priority = 0, allowedOperations = 0 } = formData
  const handleChange = (_, { name: propName, value }) => {
    onChange({ [propName]: value })
  }
  const handleSubmit = (e) => {
    e.preventDefault()
    onSubmit(formData)
  }
  const options = getLocalizedOptions(localize)
  return (
    <Form onSubmit={handleSubmit}>
      <Grid columns={4}>
        <Grid.Column mobile={16} tablet={10} computer={4}>
          <Form.Input
            type="text"
            name="wildcard"
            value={wildcard}
            onChange={handleChange}
            label={localize('SearchDataSourceByWildcard')}
            title={localize('SearchDataSourceByWildcard')}
          />
        </Grid.Column>
        <Grid.Column mobile={16} tablet={6} computer={4}>
          <Form.Select
            type="text"
            name="statUnitType"
            value={numOrZero(statUnitType)}
            onChange={handleChange}
            options={options.statUnitType}
            label={localize('StatUnit')}
            title={localize('StatUnit')}
          />
        </Grid.Column>
        <Grid.Column mobile={16} tablet={8} computer={4}>
          <Form.Select
            type="text"
            name="priority"
            value={numOrZero(priority)}
            onChange={handleChange}
            options={options.priorities}
            label={localize('Priority')}
            title={localize('Priority')}
          />
        </Grid.Column>
        <Grid.Column mobile={16} tablet={8} computer={4}>
          <Form.Select
            type="text"
            name="allowedOperations"
            value={numOrZero(allowedOperations)}
            onChange={handleChange}
            options={options.allowedOperations}
            label={localize('AllowedOperations')}
            title={localize('AllowedOperations')}
          />
        </Grid.Column>
      </Grid>
      <br />
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
