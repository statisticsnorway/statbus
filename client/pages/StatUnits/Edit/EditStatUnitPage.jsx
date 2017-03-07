import React from 'react'
import { Button } from 'semantic-ui-react'

import { cloneFormObj } from 'helpers/queryHelper'
import SchemaForm from 'components/Form'
import getField from 'components/getField'
import { getModel } from 'helpers/modelProperties'
import { wrapper } from 'helpers/locale'
import statUnitSchema from '../schema'
import styles from './styles.pcss'


const { string, shape, func } = React.PropTypes
class EditStatUnitPage extends React.Component {

  static propTypes = {
    id: string.isRequired,
    type: string.isRequired,
    actions: shape({
      fetchStatUnit: func,
    }).isRequired,
    localize: func.isRequired,
  }
  componentDidMount() {
    const { actions: { fetchStatUnit }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  handleOnChange = (e, { name, value }) => {
    this.props.actions.editForm({ name, value })
  }

  handleSubmit = (e, { formData }) => {
    e.preventDefault()
    const { type, id, actions: { submitStatUnit } } = this.props
    const data = { ...cloneFormObj(formData), regId: id }
    submitStatUnit(type, data)
  }

  renderForm() {
    const { errors, statUnit, type, localize } = this.props

    const renderButton = () => (
      <Button key="100500" className={styles.sybbtn} type="submit" primary>
        {localize('Submit')}
      </Button>
    )

    const children = [
      ...statUnit.properties.map(x => getField(x, errors[x.name], this.handleOnChange)),
      <br key="br_100500" />,
      renderButton(),
    ]

    const data = { ...getModel(statUnit.properties), type }

    return (
      <SchemaForm
        className={styles.form}
        onSubmit={this.handleSubmit}
        error
        data={data}
        schema={statUnitSchema}
      >{children}</SchemaForm>
    )
  }

  render() {
    return (
      <div className={styles.edit}>
        {this.renderForm()}
      </div>
    )
  }

}


export default wrapper(EditStatUnitPage)
