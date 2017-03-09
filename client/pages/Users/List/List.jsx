import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Loader, Table, Form } from 'semantic-ui-react'
import Griddle, { RowDefinition, ColumnDefinition } from 'griddle-react'


import rqst from 'helpers/request'
import { systemFunction as sF } from 'helpers/checkPermissions'
import { formatDateTime } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import TableHeader from './Table/TableHeader'
import TableFooter from './Table/TableFooter'
import styles from './styles'

const Item = ({ id, deleteUser, ...user, localize }) => {
  const handleDelete = () => {
    const msg = `${localize('DeleteUserMessage')} '${user.name}'. ${localize('AreYouSure')}?`
    if (confirm(msg)) {
      deleteUser(id)
    }
  }
  const bodyTable = () => (
    <Table.Body>
      <Table.Row>
        <Table.Cell>
          {sF('UserEdit')
            ? <Link to={`/users/edit/${id}`}>{user.name}</Link>
            : <span>{user.name}</span>}
        </Table.Cell>
        <Table.Cell>{user.description}</Table.Cell>
        <Table.Cell>{user.regionName}</Table.Cell>
        <Table.Cell>{user.roles.map(v => v.name).join(', ')}</Table.Cell>
        <Table.Cell>{user.creationDate}</Table.Cell>
        <Table.Cell>{user.suspensionDate}</Table.Cell>
        <Table.Cell>{user.status}</Table.Cell>
        <Table.Cell>
          <div></div>
          <Button.Group>
            {sF('UserDelete')
                && <Button
                  onClick={handleDelete}
                  icon="delete"
                  color="red"
                /> }
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    </Table.Body>
    )
  return (
    bodyTable()
  )
}

const griddleStyleConfig = {
  classNames: {
    Table: 'ui small selectable single line table sortable',
    NextButton: 'ui button',
    PreviousButton: 'ui button',
    PageDropdown: 'ui form center',
    NoResults: 'ui message',
  },
}

const GriddleDateColumn = ({ value }) => <span>{value && formatDateTime(value)}</span>
//const UserRolesColumn = ({ value }) => <span>{console.log(value.map(v => console.log(v)))}{value.map(v => v.name).join(', ')}</span>
const UserNameColumn = user => <span><UserNameColumn2 data={user} /></span>

const UserRolesColumn = user => <span className="X228">X{console.log('data')}{console.log(user)}</span>


class UserNameColumn2 extends React.Component {
  render() {
    const { value } = this.props;
    return
      <Link to={`/users/edit/${value}`}>{value}</Link>
  }
}


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
      },
      roles: undefined,
      regions: undefined,
      failure: false,
      statuses: [
        { id: '', name: 'Any user status' },
        { id: 0, name: 'Active' },
        { id: 1, name: 'Suspended' },
      ],
    }
  }

  componentDidMount() {
    this.fetchRegions()
    this.fetchRoles()
  }

  fetchRegions = () => {
    rqst({
      url: '/api/regions',
      onSuccess: (result) => {
        this.setState(() => ({ regions: result.map(v => ({ value: v.id, text: v.name })) }))
      },
      onFail: () => {
        this.setState(() => ({ regions: [], failure: true }))
      },
      onError: () => {
        this.setState(() => ({ regions: [], failure: true }))
      },
    })
  }

  fetchRoles = () => {
    rqst({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        this.setState(() => ({ roles: result.map(r => ({ value: r.id, text: r.name })) }))
      },
      onFail: () => {
        this.setState(() => ({ roles: [], failure: true }))
      },
      onError: () => {
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
    return (
      <Form loading={!(regions && roles)}>
        <Form.Group widths="equal">
          <Form.Field
            name="userName"
            placeholder="Type username"
            control="input"
            value={filter.userName}
            onChange={this.handleChange}
          />
          <Form.Select
            value={filter.roleId}
            name="roleId"
            options={[{ value: '', text: 'Any role' }, ...(roles || {})]}
            placeholder={'Any role'}
            onChange={this.handleSelect}
            search
            error={!roles}
          />
          <Form.Select
            value={filter.regionId}
            name="regionId"
            options={[{ value: '', text: localize('RegionNotSelected') }, ...(regions || {})]}
            placeholder={localize('RegionNotSelected')}
            onChange={this.handleSelect}
            search
            error={!regions}
          />
          <Form.Select
            value={filter.status}
            name="status"
            options={this.state.statuses.map(r => ({ value: r.id, text: r.name }))}
            placeholder="Any user status"
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

FilterList.propTypes = {
  localize: React.PropTypes.func.isRequired,
  onChange: React.PropTypes.func.isRequired,
}

class TableHeaderColumn extends React.Component {
}

class UsersList extends React.Component {
  componentDidMount() {
    const { filter } = this.props
    this.props.fetchUsers(filter)
  }

  onNext = () => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: filter.page + 1})
  }

  onPrevious = () => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: filter.page - 1})
  }

  onGetPage = (pageNumber) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, page: pageNumber })
  }

  onFilter = (data) => {
    const { filter } = this.props
    this.props.fetchUsers({ ...filter, ...data })
  }

  onSort = (sort) => {
    switch (sort.id) {
      case 'name':
      case 'regionName':
      case 'creationDate':
        const { filter } = this.props
        this.props.fetchUsers({
          ...filter,
          sortColumn: sort.id,
          sortAscending: filter.sortColumn !== sort.id || !filter.sortAscending,
        })
        break
      default:
        break
    }
  }

  render() {
    const { filter, users, totalCount, totalPages, editUser, deleteUser, status, localize } = this.props
    return (
      <div>
        <div className={styles['add-user']}>
          <h2>{localize('UsersList')}</h2>
          {sF('UserCreate')
            && <Button
              as={Link} to="/users/create"
              content={localize('CreateUserButton')}
              icon={<Icon size="large" name="user plus" />}
              size="medium"
              color="green"
            />}
        </div>
        <div className={styles['list-root']}>
          <Loader active={status === 1} />
          <div className={styles.addUser} />

          <Griddle
            data={users}
            pageProperties={{
              currentPage: filter.page,
              pageSize: filter.pageSize,
              recordCount: totalCount,
            }}
            events={{
              onNext: this.onNext,
              onPrevious: this.onPrevious,
              onGetPage: this.onGetPage,
              onSort: this.onSort,
            }}
            components={{
              Filter: () => <FilterList localize={localize} onChange={this.onFilter} />,
              SettingsToggle: () => <span />,
            }}
            sortProperties={[{ id: filter.sortColumn, sortAscending: filter.sortAscending }]}
            styleConfig={griddleStyleConfig}
          >
            <RowDefinition>
              <ColumnDefinition id="name" title={localize('UserName')} />
              <ColumnDefinition id="description" title={localize('Description')} sortable={false} />
              <ColumnDefinition id="regionName" title={localize('Region')} />
              <ColumnDefinition id="roles" title="[ROLES]" customComponent={UserRolesColumn} sortable={false} />
              <ColumnDefinition id="creationDate" title="[CREAT DATE]" customComponent={GriddleDateColumn} />
              {/*<ColumnDefinition id="suspensionDate" title="" customComponent={GriddleDateColumn} />*/}
              <ColumnDefinition id="status" title="[STATUS]" />
            </RowDefinition>
          </Griddle>

          <Table singleLine selectable className="sortable" size="small">
            <TableHeader sortProperties={{ id: filter.sortColumn, sortAscending: filter.sortAscending }} />
            {users && users.map(u =>
              <Item {...{ ...u, key: u.id, deleteUser, localize }} />)}
            <TableFooter totalCount={totalCount} totalPages={totalPages} />
          </Table>
        </div>
      </div>
    )
  }
}

Item.propTypes = { localize: React.PropTypes.func.isRequired }
UsersList.propTypes = {
  localize: React.PropTypes.func.isRequired,
  fetchUsers: React.PropTypes.func.isRequired,
  filter: React.PropTypes.shape({
    page: React.PropTypes.number.isRequired,
    pageSize: React.PropTypes.number.isRequired,
  }).isRequired,
}

export default wrapper(UsersList)
