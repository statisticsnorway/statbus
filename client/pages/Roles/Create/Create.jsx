import React from 'react'
import { Button, Form, Loader } from 'semantic-ui-react'

import rqst from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class CreateForm extends React.Component {
  state = {
    standardDataAccess: [],
    systemFunctions: [],
    fetchingStandardDataAccess: true,
    fetchingSystemFunctions: true,
    standardDataAccessMessage: undefined,
    systemFunctionsFailMessage: undefined,
  }
  componentDidMount() {
    this.fetchStandardDataAccess()
    this.fetchSystemFunctions()
  }
  fetchStandardDataAccess() {
    rqst({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        this.setState(s => ({
          ...s,
          standardDataAccess: result,
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          ...s,
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
      onError: () => {
        this.setState(s => ({
          ...s,
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
        this.setState(s => ({
          ...s,
          systemFunctions: result,
          fetchingSystemFunctions: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          ...s,
          systemFunctionsFailMessage: 'failed loading system functions',
          fetchingSystemFunctions: false,
        }))
      },
      onError: () => {
        this.setState(s => ({
          ...s,
          systemFunctionsFailMessage: 'error while fetching system functions',
          fetchingSystemFunctions: false,
        }))
      },
    })
  }
  render() {
    const { submitRole, localize } = this.props
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      submitRole(formData)
    }
    return (
      <div className={styles.rolecreate}>
        <Form className={styles.form} onSubmit={handleSubmit}>
          <h2>{localize('CreateNewRole')}</h2>
          <Form.Input
            name="name"
            label={localize('RoleName')}
            placeholder={localize('WebSiteVisitor')}
            required
          />
          <Form.Input
            name="description"
            required
            label={localize('Description')}
            placeholder={localize('OrdinaryWebsiteUser')}
          />
          {this.state.fetchingStandardDataAccess
            ? <Loader content="fetching standard data access" />
            : <Form.Select
              options={this.state.standardDataAccess.map(r => ({ value: r, text: r }))}
              name="standardDataAccess"
              label={localize('StandardDataAccess')}
              placeholder={localize('SelectOrSearchStandardDataAccess')}
              required
              multiple
              search
            />}
          {this.state.fetchingSystemFunctions
            ? <Loader content="fetching system functions" />
            : <Form.Select
              options={this.state.systemFunctions.map(r => ({ value: r.key, text: r.value }))}
              name="accessToSystemFunctions"
              required
              label={localize('AccessToSystemFunctions')}
              placeholder={localize('SelectOrSearchSystemFunctions')}
              multiple
              search
            />}
          <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
        </Form>
      </div>
    )
  }
}

CreateForm.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(CreateForm)
