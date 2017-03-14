import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'

import FunctionalAttributes from 'components/FunctionalAttributes'
import DataAccess from 'components/DataAccess'
import rqst from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class CreateForm extends React.Component {
  state = {
    standardDataAccess: {
      localUnit: [],
      legalUnit: [],
      enterpriseGroup: [],
      enterpriseUnit: [],
    },
    fetchingStandardDataAccess: true,
    standardDataAccessMessage: undefined,
    accessToSystemFunctions: []
  }
  componentDidMount() {
    this.fetchStandardDataAccess()
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
  
  handleAccessToSystemFunctionsChange = (e) => {
    this.setState(s => ({
      ...s,
      accessToSystemFunctions: e.value
        ? [...s.accessToSystemFunctions, e.name]
        : s.accessToSystemFunctions.filter(x => x !== e.name)
    }))
  }
  render() {
    const { submitRole, localize } = this.props
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      submitRole({
        ...formData, 
        dataAccess: this.state.standardDataAccess, 
        accessToSystemFunctions: this.state.accessToSystemFunctions ,
        hidden: null,
      })
    }
    const handleDataAccessChange = (e) => {
      this.setState(s => {
        const item = this.state.standardDataAccess[e.type].find(x => x.name == e.name)
        const items = this.state.standardDataAccess[e.type].filter(x => x.name != e.name)
        return ({
          ...s,
          standardDataAccess: { ...s.standardDataAccess, [e.type]: [...items, { ...item, allowed: !item.allowed }] }
        })
      })
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
            : <DataAccess
              dataAccess={this.state.standardDataAccess}
              label={localize('DataAccess')}
              onChange={handleDataAccessChange}
            />}
          <FunctionalAttributes
            label={localize('AccessToSystemFunctions')}
            accessToSystemFunctions={this.state.accessToSystemFunctions}
            onChange={this.handleAccessToSystemFunctionsChange}
          />
          <Button
            as={Link} to="/roles"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="gray"
            type="button"
          />
          <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
        </Form>
      </div>
    )
  }
}

CreateForm.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(CreateForm)
