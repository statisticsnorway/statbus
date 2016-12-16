import React, { Component, PropTypes } from 'react'
import { Button, Form } from 'semantic-ui-react'

import statUnitTypes from '../../../helpers/statUnitTypes'

class SearchForm extends Component {
  static propTypes = {
    search: PropTypes.func.isRequired,
  }
  name = 'StatUnitSearchBox'
  render() {
    const { search } = this.props
    const defaultType = { value: 'any', text: 'Any type' }
    const typeOptions = [
      defaultType,
      ...statUnitTypes.map(x => ({ value: x.key, text: x.value })),
    ]
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      const queryParams = {
        ...formData,
        type: formData.type === defaultType.value
          ? null
          : formData.type,
      }
      search(queryParams)
    }
    return (
      <Form onSubmit={handleSubmit}>
        <Form.Input
          name="wildcard"
          label="Search wildcard"
          placeholder="search..."
          size="large"
        />
        <Form.Select
          name="type"
          label="Statistical unit type"
          options={typeOptions}
          defaultValue={typeOptions[0].value}
          size="large"
          search
        />
        <Form.Checkbox
          name="includeLiquidated"
          label="Include liquidated"
        />
        <Form.Input
          name="turnoverFrom"
          label="Turnover from"
          type="number"
        />
        <Form.Input
          name="turnoverTo"
          label="Turnover to"
          type="number"
        />
        <Form.Input
          name="numberOfEmployyesFrom"
          label="Number of employyes from"
          type="number"
        />
        <Form.Input
          name="numberOfEmployyesTo"
          label="Number of employyes to"
          type="number"
        />
        <Button
          labelPosition="left"
          icon="search"
          content="Search"
          type="submit"
          primary
        />
      </Form>
    )
  }
}

export default SearchForm
