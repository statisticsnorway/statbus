import React from 'react'
import { Form, Button } from 'semantic-ui-react'

import UnitSearch, { defaultUnitSearchResult } from '../Components/UnitSearch'

const { func, shape, object, string } = React.PropTypes

class ViewFilter extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    onFilter: func.isRequired,
    value: shape({
      source: object,
      name: string,
    }),
  }

  static defaultProps = {
    value: {
      source: undefined,
      name: '',
    },
  }

  state = {
    data: this.props.value,
  }

  onFieldChanged = (e, { name, value }) => {
    this.setState(s => ({
      data: {
        ...s.data,
        [name]: value,
      },
    }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    console.log('Filter', this.state.data)
    this.props.onFilter(this.state.data)
  }

  render() {
    const { localize } = this.props
    const { source, name } = this.state.data
    return (
      <Form onSubmit={this.handleSubmit}>
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
