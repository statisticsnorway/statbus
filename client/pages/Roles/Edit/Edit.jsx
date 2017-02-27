import React from 'react'
import { Button, Form, Loader } from 'semantic-ui-react'

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
    standardDataAccess: [],
    systemFunctions: [],
    fetchingStandardDataAccess: true,
    fetchingSystemFunctions: true,
    standardDataAccessMessage: undefined,
    systemFunctionsFailMessage: undefined,
  }

  componentDidMount() {
    this.props.fetchRole(this.props.id)
    this.fetchStandardDataAccess()
    this.fetchSystemFunctions()
  }

  fetchStandardDataAccess() {
    rqst({
      url: '/api/accessAttributes/dataAttributes',
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

  fetchSystemFunctions() {
    rqst({
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
      onError: () => {
        this.setState(({
          systemFunctionsFailMessage: 'error while fetching system functions',
          fetchingSystemFunctions: false,
        }))
      },
    })
  }

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitRole(this.props.role)
  }

  render() {
    const { role, localize } = this.props
    const {
      fetchingStandardDataAccess, standardDataAccess,
      fetchingSystemFunctions, systemFunctions,
    } = this.state
    const sdaOptions = standardDataAccess.map(r => ({ value: r, text: localize(r) }))
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
              : <Form.Select
                value={role.standardDataAccess}
                onChange={this.handleEdit}
                options={sdaOptions}
                name="standardDataAccess"
                label={localize('StandardDataAccess')}
                placeholder={localize('SelectOrSearchStandardDataAccess')}
                multiple
                search
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
            <Button className={styles.sybbtn} type="submit" primary>
              {localize('Submit')}
            </Button>
          </Form>}
      </div>
    )
  }
}

export default wrapper(Edit)
