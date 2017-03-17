import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'

import DataAccess from 'components/DataAccess'
import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func } = React.PropTypes

class Edit extends React.Component {
  static propTypes = {
    editForm: func.isRequired,
    fetchRole: func.isRequired,
    submitRole: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    standardDataAccess: {
      localUnit: [],
      legalUnit: [],
      enterpriseGroup: [],
      enterpriseUnit: [],
    },
    systemFunctions: [],
    fetchingStandardDataAccess: true,
    fetchingSystemFunctions: true,
    standardDataAccessMessage: undefined,
    systemFunctionsFailMessage: undefined,
  }

  componentDidMount() {
    this.props.fetchRole(this.props.id)
    this.fetchStandardDataAccess(this.props.id)
    this.fetchSystemFunctions()
  }

  fetchStandardDataAccess(roleId) {
    internalRequest({
      url: `/api/accessAttributes/dataAttributesByRole/${roleId}`,
      onSuccess: (result) => {
        this.setState(({
          standardDataAccess: result,
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(({
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }

  fetchSystemFunctions() {
    internalRequest({
      url: '/api/accessAttributes/systemFunctions',
      onSuccess: (result) => {
        this.setState(({
          systemFunctions: result,
          fetchingSystemFunctions: false,
        }))
      },
      onFail: () => {
        this.setState(({
          systemFunctionsFailMessage: 'failed loading system functions',
          fetchingSystemFunctions: false,
        }))
      },
    })
  }

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleDataAccessChange = (data) => {
    this.setState((s) => {
      const item = s.standardDataAccess[data.type].find(x => x.name == data.name)
      const items = s.standardDataAccess[data.type].filter(x => x.name != data.name)
      return ({
        standardDataAccess: { ...s.standardDataAccess, [data.type]: [...items, { ...item, allowed: !item.allowed }] }
      })
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitRole({
      ...this.props.role,
      dataAccess: this.state.standardDataAccess,
    })
  }

  render() {
    const { role, localize } = this.props
    const {
      fetchingStandardDataAccess, fetchingSystemFunctions, systemFunctions,
    } = this.state
    const sfOptions = systemFunctions.map(x => ({ value: x.key, text: localize(x.value) }))
    return (
      <div className={styles.roleEdit}>
        {role === undefined
          ? <Loader active />
          : <Form className={styles.form} onSubmit={this.handleSubmit}>
            <h2>{localize('EditRole')}</h2>
            <Form.Input
              value={role.name}
              onChange={this.handleEdit}
              name="name"
              label={localize('RoleName')}
              placeholder={localize('WebSiteVisitor')}
            />
            <Form.Input
              value={role.description}
              onChange={this.handleEdit}
              name="description"
              label={localize('Description')}
              placeholder={localize('OrdinaryWebsiteUser')}
            />
            {fetchingStandardDataAccess
              ? <Loader content={localize('fetching standard data access')} />
              : <DataAccess
                dataAccess={this.state.standardDataAccess}
                label={localize('DataAccess')}
                onChange={this.handleDataAccessChange}
              />}
            {fetchingSystemFunctions
              ? <Loader content={localize('fetching system functions')} />
              : <Form.Select
                value={role.accessToSystemFunctions}
                onChange={this.handleEdit}
                options={sfOptions}
                name="accessToSystemFunctions"
                label={localize('AccessToSystemFunctions')}
                placeholder={localize('SelectOrSearchSystemFunctions')}
                multiple
                search
              />}
            <Button
              as={Link} to="/roles"
              content={localize('Back')}
              icon={<Icon size="large" name="chevron left" />}
              size="small"
              color="grey"
              type="button"
            />
            <Button
              content={localize('Submit')}
              className={styles.sybbtn}
              type="submit"
              primary
            />
          </Form>}
      </div>
    )
  }
}

export default wrapper(Edit)
