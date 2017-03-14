import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'
import DataAccess from 'components/DataAccess'
import FunctionalAttributes from 'components/FunctionalAttributes'

import rqst from 'helpers/request'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class Edit extends React.Component {
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
  render() {
    const { role, editForm, submitRole, localize } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitRole({ ...role, dataAccess: this.state.standardDataAccess })
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    const handleSelect = (e, { name, value }) => { editForm({ propName: name, value }) }
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
    const handleAccessToSystemFunctionsChange = (e) => editForm({
      propName: 'accessToSystemFunctions',
      value: e.value
        ? [...role.accessToSystemFunctions, e.name]
        : role.accessToSystemFunctions.filter(x => x !== e.name)
    })

    return (
      <div className={styles.roleEdit}>
        {role === undefined
          ? <Loader active />
          : <Form className={styles.form} onSubmit={handleSubmit}>
            <h2>{localize('EditRole')}</h2>
            <Form.Input
              value={role.name}
              onChange={handleChange('name')}
              name="name"
              label={localize('RoleName')}
              placeholder={localize('WebSiteVisitor')}
            />
            <Form.Input
              value={role.description}
              onChange={handleChange('description')}
              name="description"
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
              accessToSystemFunctions={role.accessToSystemFunctions}
              onChange={handleAccessToSystemFunctionsChange}
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
          </Form>}
      </div>
    )
  }
}

Edit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Edit)
