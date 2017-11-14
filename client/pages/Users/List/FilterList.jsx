import React from 'react'
import { func, shape } from 'prop-types'
import { Button, Icon, Form } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'
import { userStatuses } from 'helpers/enums'

const statuses = [['', 'UserStatusAny'], ...userStatuses]

class FilterList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    onChange: func.isRequired,
    filter: shape({}).isRequired,
  }

  state = {
    filter: {
      userName: '',
      roleId: '',
      status: '',
      ...this.props.filter,
    },
    roles: undefined,
    failure: false,
  }

  componentDidMount() {
    this.fetchRoles()
  }

  fetchRoles = () => {
    internalRequest({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        this.setState(() => ({ roles: result.map(r => ({ value: r.id, text: r.name })) }))
      },
      onFail: () => {
        this.setState(() => ({ roles: [], failure: true }))
      },
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    const { onChange } = this.props
    onChange(this.state.filter)
  }

  handleChange = (e) => {
    e.persist()
    this.setState(s => ({ filter: { ...s.filter, [e.target.name]: e.target.value } }))
  }

  handleSelect = (e, { name, value }) => {
    e.persist()
    this.setState(s => ({ filter: { ...s.filter, [name]: value } }))
  }

  render() {
    const { filter, roles } = this.state
    const { localize } = this.props
    const statusesList = statuses.map(kv => ({ value: kv[0], text: localize(kv[1]) }))
    return (
      <Form loading={!roles}>
        <Form.Group widths="equal">
          <Form.Field
            name="userName"
            placeholder={localize('UserName')}
            control="input"
            value={filter.userName}
            onChange={this.handleChange}
          />
          <Form.Select
            value={filter.roleId}
            name="roleId"
            options={[{ value: '', text: localize('RolesAll') }, ...(roles || [])]}
            placeholder={localize('RolesAll')}
            onChange={this.handleSelect}
            search
            error={!roles}
          />
          <Form.Select
            value={filter.status}
            name="status"
            options={statusesList}
            placeholder={localize('UserStatusAny')}
            onChange={this.handleSelect}
          />
          <Button type="submit" icon onClick={this.handleSubmit}>
            <Icon name="filter" />
          </Button>
        </Form.Group>
      </Form>
    )
  }
}

export default FilterList
