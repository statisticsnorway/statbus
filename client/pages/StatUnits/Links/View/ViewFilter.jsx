import React from 'react'
import { Icon, Form, Button } from 'semantic-ui-react'

import UnitSearch from '../Components/UnitSearch'

const { func, shape, object, string, bool } = React.PropTypes

class ViewFilter extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    isLoading: bool,
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
      extended: false,
    },
    isLoading: false,
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

  onSearchModeToggle = () => {
    this.setState((s) => {
      const isExtended = !s.data.extended
      return isExtended
        ? { data: { ...s.data, extended: isExtended } }
        : { data: { source: s.data.source, name: s.data.name, extended: isExtended } }
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.onFilter(this.state.data)
  }

  render() {
    const { localize, isLoading } = this.props
    const {
      source,
      name,
      turnoverFrom,
      turnoverTo,
      employeesFrom,
      employeesTo,
      geographicalCode,
      dataSource,
      extended,
    } = this.state.data
    return (
      <Form onSubmit={this.handleSubmit} loading={isLoading}>
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
          <span onClick={this.onSearchModeToggle} style={{ cursor: 'pointer' }}>
            <Icon name="search" />
            {localize(extended ? 'SearchDefault' : 'SearchExtended')}
          </span>
        </Form.Field>
        {extended &&
          <div>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('TurnoverFrom')}
                name="turnoverFrom"
                value={turnoverFrom || ''}
                onChange={this.onFieldChanged}
                type="number"
              />
              <Form.Input
                label={localize('TurnoverTo')}
                name="turnoverTo"
                value={turnoverTo || ''}
                onChange={this.onFieldChanged}
                type="number"
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('NumberOfEmployeesFrom')}
                name="employeesFrom"
                value={employeesFrom || ''}
                onChange={this.onFieldChanged}
                type="number"
              />
              <Form.Input
                label={localize('NumberOfEmployeesTo')}
                name="employeesTo"
                value={employeesTo || ''}
                onChange={this.onFieldChanged}
                type="number"
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('GeographicalCode')}
                name="geographicalCode"
                value={geographicalCode || ''}
                onChange={this.onFieldChanged}
                type="number"
              />
              <Form.Input
                label={localize('DataSource')}
                name="dataSource"
                value={dataSource || ''}
                onChange={this.onFieldChanged}
              />
            </Form.Group>
          </div>
        }
        <Form.Field>
          <Button color="green">{localize('Search')}</Button>
        </Form.Field>
      </Form>
    )
  }
}

export default ViewFilter
