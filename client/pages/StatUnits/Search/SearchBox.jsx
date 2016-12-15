import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import statUnitTypes from '../../../helpers/statUnitTypes'

const { func, shape, string } = React.PropTypes

class SearchForm extends React.Component {
  static propTypes = {
    searchParams: shape({
      wildcard: string,
      type: string,
    }).isRequired,
    search: func.isRequired,
  }
  static defaultProps = {
    searchParams: {
      wildcard: '',
    },
  }
  name = 'StatUnitSearchBox'
  render() {
    const { searchParams, search } = this.props
    // TODO: get form values, not from props!!!
    const handleSearch = (e) => {
      e.preventDefault()
      search(searchParams)
    }
    const typeOptions = [
      { text: 'Any type', value: 'null' },
      ...statUnitTypes.map(x => ({ text: x, value: x })),
    ]
    return (
      <Form onSubmit={handleSearch}>
        <Form.Input
          name="wildcard"
          label="Search wildcard"
          placeholder="search..."
          size="large"
        />
        <Form.Dropdown
          name="type"
          label="Statistical unit type"
          options={typeOptions}
          defaultValue={typeOptions[0].value}
        />
        <Button
          type="submit"
          color="teal"
          labelPosition="left"
          icon="search"
          content="Search"
        />
      </Form>
    )
  }
}

export default SearchForm
