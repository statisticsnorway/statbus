import React from 'react'
import { Link } from 'react-router'
import { Button, Icon } from 'semantic-ui-react'

import SchemaForm from 'components/Form'
import getField from 'components/getField'
import { getModel } from 'helpers/modelProperties'
import { wrapper } from 'helpers/locale'
import { getSchema } from '../schema'
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
    statUnit: shape().isRequired,
  }

  componentDidMount() {
    const { actions: { fetchStatUnit }, id, type } = this.props
    fetchStatUnit(type, id)
  }

  handleOnChange = (e, { name, value }) => {
    this.props.actions.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    const { type, id, statUnit, actions: { submitStatUnit } } = this.props
    const data = { ...getModel(statUnit.properties), regId: id }
    submitStatUnit(type, data)
  }

  renderForm() {
    const { errors, statUnit, type, localize } = this.props

    const renderBackButton = () => (
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        floated="left"
        size="small"
        color="grey"
        type="button"
      />
    )

    const renderSubmitButton = () => (
      <Button
        key="100500"
        content={localize('Submit')}
        floated="right"
        type="submit"
        primary
      />
    )

    const children = [
      ...statUnit.properties.map(x => getField(x, errors[x.name], this.handleOnChange)),
      <br key="br_100500" />,
      renderBackButton(),
      renderSubmitButton(),
    ]

    const data = { ...getModel(statUnit.properties), type }

    return (
      <SchemaForm
        className={styles.form}
        onSubmit={this.handleSubmit}
        error
        data={data}
        schema={getSchema(type)}
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
