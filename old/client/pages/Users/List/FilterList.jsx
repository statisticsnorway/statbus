import React, { useState, useEffect } from 'react'
import { func, shape } from 'prop-types'
import { Button, Icon, Form } from 'semantic-ui-react'
import { internalRequest } from '/helpers/request'
import { userStatuses } from '/helpers/enums'

const statuses = [['', 'UserStatusAny'], ...userStatuses]

const FilterList = ({ localize, onChange, filter }) => {
  const [roles, setRoles] = useState([])
  const [filterState, setFilterState] = useState({
    userName: '',
    roleId: '',
    status: 2,
    ...filter,
  })

  useEffect(() => {
    fetchRoles()
  }, [])

  const fetchRoles = () => {
    internalRequest({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        setRoles(result.map(r => ({ value: r.id, text: r.name })))
      },
      onFail: () => {
        setRoles([])
      },
    })
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    onChange(filterState)
  }

  const handleChange = (e) => {
    e.persist()
    setFilterState(prevFilter => ({ ...prevFilter, [e.target.name]: e.target.value }))
  }

  const handleSelect = (e, { name, value }) => {
    e.persist()
    setFilterState(prevFilter => ({ ...prevFilter, [name]: value }))
  }

  const statusesList = statuses.map(kv => ({ value: kv[0], text: localize(kv[1]) }))
  const rolesList = roles.map(roleObJ => ({ value: roleObJ.value, text: localize(roleObJ.text) }))

  return (
    <Form loading={!roles.length}>
      <Form.Group widths="equal">
        <Form.Field
          name="userName"
          placeholder={localize('UserName')}
          control="input"
          value={filterState.userName}
          onChange={handleChange}
        />
        <Form.Select
          value={filterState.roleId}
          name="roleId"
          options={[{ value: '', text: localize('RolesAll') }, ...(rolesList || [])]}
          placeholder={localize('RolesAll')}
          onChange={handleSelect}
          search
          error={!roles.length}
        />
        <Form.Select
          value={filterState.status}
          name="status"
          options={statusesList}
          placeholder={localize('UserStatusAny')}
          onChange={handleSelect}
        />
        <Button type="submit" icon onClick={handleSubmit}>
          <Icon name="filter" />
        </Button>
      </Form.Group>
    </Form>
  )
}

FilterList.propTypes = {
  localize: func.isRequired,
  onChange: func.isRequired,
  filter: shape({}).isRequired,
}

export default FilterList
