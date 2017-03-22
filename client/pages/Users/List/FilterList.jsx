import React from 'react'
import { Button, Icon, Form } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import statuses from 'helpers/userStatuses'

class FilterList extends React.Component {
  constructor(props) {
    super(props)
    this.handleChange = this.handleChange.bind(this)
    this.handleSelect = this.handleSelect.bind(this)
    this.handleSubmit = this.handleSubmit.bind(this)
    this.state = {
      filter: {
        userName: '',
        roleId: '',
        regionId: '',
        status: '',
        ...this.props.filter,
      },
      roles: undefined,
      regions: undefined,
      failure: false,
    }
  }

  componentDidMount() {
    this.fetchRegions()
    this.fetchRoles()
  }

  fetchRegions = () => {
    internalRequest({
      url: '/api/regions',
      onSuccess: (result) => {
        this.setState(() => ({ regions: result.map(v => ({ value: v.id, text: v.name })) }))
      },
      onFail: () => {
        this.setState(() => ({ regions: [], failure: true }))
      },
    })
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

  handleSubmit(e) {
    e.preventDefault()
    const { onChange } = this.props
    onChange(this.state.filter)
  }

  handleChange(e) {
    e.persist()
    this.setState(s => ({ filter: { ...s.filter, [e.target.name]: e.target.value } }))
  }

  handleSelect(e, { name, value }) {
    e.persist()
    this.setState(s => ({ filter: { ...s.filter, [name]: value } }))
  }

  render() {
    const { filter, regions, roles } = this.state
    const { localize } = this.props
    const statusesList = [
      { value: '', text: localize('UserStatusAny') },
      ...statuses.map(r => ({ value: r.key, text: localize(r.value) })),
    ]
    return (
      <Form loading={!(regions && roles)}>
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
            value={filter.regionId}
            name="regionId"
            options={[{ value: '', text: localize('RegionAll') }, ...(regions || [])]}
            placeholder={localize('RegionAll')}
            onChange={this.handleSelect}
            search
            error={!regions}
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

const { func, object } = React.PropTypes

FilterList.propTypes = {
  localize: func.isRequired,
  onChange: func.isRequired,
  filter: object.isRequired,
}

export default wrapper(FilterList)
