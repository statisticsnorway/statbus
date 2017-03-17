import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'

import DataAccess from 'components/DataAccess'
import FunctionalAttributes from 'components/FunctionalAttributes'

import rqst from 'helpers/request'
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
    fetchingStandardDataAccess: true,
    standardDataAccessMessage: undefined,

  }

  componentDidMount() {
    this.props.fetchRole(this.props.id)
    this.fetchStandardDataAccess(this.props.id)

  }

  fetchStandardDataAccess(roleId) {
    rqst({
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
      onError: () => {
        this.setState(({
          standardDataAccessFailMessage: 'error while fetching standard data access',
          fetchingStandardDataAccess: false,
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

  handleAccessToSystemFunctionsChange = (e) => this.props.editForm({
    name: e.name,
    value: e.checked
      ? [...this.props.role.accessToSystemFunctions, e.value]
      : this.props.role.accessToSystemFunctions.filter(x => x !== e.value)
  })

  render() {
    const { role, editForm, submitRole, localize } = this.props
    const { fetchingStandardDataAccess } = this.state

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
              placeholder={localize('RoleNamePlaceholder')}
            />
            <Form.Input
              value={role.description}
              onChange={this.handleEdit}
              name="description"
              label={localize('Description')}
              placeholder={localize('RoleDescriptionPlaceholder')}
            />
            {fetchingStandardDataAccess
              ? <Loader content={localize('fetching standard data access')} />
              : <DataAccess
                value={this.state.standardDataAccess}
                label={localize('DataAccess')}
                onChange={this.handleDataAccessChange}
              />}
            <FunctionalAttributes
              label={localize('AccessToSystemFunctions')}
              value={role.accessToSystemFunctions}
              onChange={this.handleAccessToSystemFunctionsChange}
              name="accessToSystemFunctions"
            />
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
