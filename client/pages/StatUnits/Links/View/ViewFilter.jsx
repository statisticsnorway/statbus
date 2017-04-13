import React from 'react'
import { Form, Button } from 'semantic-ui-react'

import UnitSearch, { defaultUnitSearchResult } from '../Components/UnitSearch'

const { func } = React.PropTypes

class ViewFilter extends React.Component {
  static propTypes = {
    localize: func.isRequired,
  }

  state = {
    source: defaultUnitSearchResult,
    name: '',
  }

  onFieldChanged = (e, { name, value }) => {
    this.setState(s => ({
      ...s,
      [name]: value,
    }))
  }

  onSubmit = (e) => {
    e.preventDefault()
    alert('test')
  }

  render() {
    const { localize } = this.props
    const { source, name } = this.state
    return (
      <Form onSubmit={this.onSubmit}>
        <UnitSearch
          value={source}
          name="source"
          localize={localize}
          onChange={this.onFieldChanged}
        />
        <Form.Input
          label={localize('Name')}
          name="name"
          value={name}
          onChange={this.onFieldChanged}
        />
        <Form.Field>
          <Button color="green">{localize('Search')}</Button>
        </Form.Field>
      </Form>
    )
  }
}

export default ViewFilter
